package forgeui.bridge;

import io.netty.bootstrap.ServerBootstrap;
import io.netty.buffer.Unpooled;
import io.netty.channel.Channel;
import io.netty.channel.ChannelFutureListener;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.SimpleChannelInboundHandler;
import io.netty.channel.group.ChannelGroup;
import io.netty.channel.group.DefaultChannelGroup;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import io.netty.handler.codec.http.DefaultFullHttpResponse;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpHeaderNames;
import io.netty.handler.codec.http.HttpObjectAggregator;
import io.netty.handler.codec.http.HttpResponseStatus;
import io.netty.handler.codec.http.HttpServerCodec;
import io.netty.handler.codec.http.HttpVersion;
import io.netty.handler.codec.http.websocketx.TextWebSocketFrame;
import io.netty.handler.codec.http.websocketx.WebSocketServerProtocolHandler;
import io.netty.util.concurrent.GlobalEventExecutor;

import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.util.function.Consumer;
import java.util.function.BiConsumer;

/**
 * Local HTTP + WebSocket server. Serves the bundled test page from {@code /web} on the classpath and
 * carries JSON messages on {@code /ws}. Binds to loopback only, unless built with {@link #exposed}: that form
 * listens on every interface for online players, serves no files and refuses browsers. Its callers authenticate.
 */
final class BridgeServer {
    private final int port;
    private final boolean exposed;
    private final ChannelGroup clients = new DefaultChannelGroup(GlobalEventExecutor.INSTANCE);
    private final BiConsumer<Channel, String> onMessage;
    private final Consumer<Channel> onConnect;
    private final Consumer<Channel> onDisconnect;
    private Channel listener;
    private EventLoopGroup boss;
    private EventLoopGroup workers;

    BridgeServer(int port, BiConsumer<Channel, String> onMessage, Consumer<Channel> onConnect) {
        this(port, false, onMessage, onConnect, channel -> {});
    }

    BridgeServer(int port, BiConsumer<Channel, String> onMessage, Consumer<Channel> onConnect, Consumer<Channel> onDisconnect) {
        this(port, false, onMessage, onConnect, onDisconnect);
    }

    private BridgeServer(int port, boolean exposed, BiConsumer<Channel, String> onMessage, Consumer<Channel> onConnect, Consumer<Channel> onDisconnect) {
        this.port = port;
        this.exposed = exposed;
        this.onMessage = onMessage;
        this.onConnect = onConnect;
        this.onDisconnect = onDisconnect;
    }

    static BridgeServer exposed(int port, BiConsumer<Channel, String> onMessage, Consumer<Channel> onConnect, Consumer<Channel> onDisconnect) {
        return new BridgeServer(port, true, onMessage, onConnect, onDisconnect);
    }

    void start() throws InterruptedException {
        boss = new NioEventLoopGroup(1);
        workers = new NioEventLoopGroup(2);
        listener = new ServerBootstrap()
                .group(boss, workers)
                .channel(NioServerSocketChannel.class)
                .childHandler(new ChannelInitializer<SocketChannel>() {
                    @Override
                    protected void initChannel(SocketChannel ch) {
                        ch.pipeline().addLast(new HttpServerCodec());
                        ch.pipeline().addLast(new HttpObjectAggregator(1 << 20));
                        ch.pipeline().addLast(new OriginHandler());
                        ch.pipeline().addLast(new WebSocketServerProtocolHandler("/ws", null, true, 1 << 22));
                        ch.pipeline().addLast(new StaticHandler(!exposed));
                        ch.pipeline().addLast(new SocketHandler());
                    }
                })
                .bind(exposed ? new InetSocketAddress(port) : new InetSocketAddress("127.0.0.1", port)).sync().channel();
    }

    int localPort() { return ((InetSocketAddress) listener.localAddress()).getPort(); }

    void close() {
        if (listener != null) listener.close().syncUninterruptibly();
        clients.close().awaitUninterruptibly();
        if (workers != null) workers.shutdownGracefully(0, 2, java.util.concurrent.TimeUnit.SECONDS).syncUninterruptibly();
        if (boss != null) boss.shutdownGracefully(0, 2, java.util.concurrent.TimeUnit.SECONDS).syncUninterruptibly();
    }

    void broadcast(String json) {
        clients.writeAndFlush(new TextWebSocketFrame(json));
    }

    void send(Channel ch, String json) {
        ch.writeAndFlush(new TextWebSocketFrame(json));
    }

    private final class SocketHandler extends SimpleChannelInboundHandler<TextWebSocketFrame> {
        @Override
        public void userEventTriggered(ChannelHandlerContext ctx, Object evt) throws Exception {
            if (evt instanceof WebSocketServerProtocolHandler.HandshakeComplete) {
                clients.add(ctx.channel());
                onConnect.accept(ctx.channel());
            }
            super.userEventTriggered(ctx, evt);
        }

        @Override
        public void channelInactive(ChannelHandlerContext ctx) throws Exception {
            onDisconnect.accept(ctx.channel());
            super.channelInactive(ctx);
        }

        @Override
        public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
            ctx.close(); // client went away; nothing to do
        }

        @Override
        protected void channelRead0(ChannelHandlerContext ctx, TextWebSocketFrame frame) {
            try {
                onMessage.accept(ctx.channel(), frame.text());
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    /** Native clients omit Origin; browser clients must come from our local test page. */
    private final class OriginHandler extends SimpleChannelInboundHandler<FullHttpRequest> {
        @Override protected void channelRead0(ChannelHandlerContext ctx, FullHttpRequest req) {
            String origin = req.headers().get(HttpHeaderNames.ORIGIN);
            if (req.uri().split("\\?")[0].equals("/ws") && origin != null
                    && (exposed || (!origin.equals("http://127.0.0.1:" + localPort())
                    && !origin.equals("http://localhost:" + localPort())))) {
                FullHttpResponse response = new DefaultFullHttpResponse(HttpVersion.HTTP_1_1, HttpResponseStatus.FORBIDDEN);
                response.headers().setInt(HttpHeaderNames.CONTENT_LENGTH, 0);
                ctx.writeAndFlush(response).addListener(ChannelFutureListener.CLOSE);
                return;
            }
            ctx.fireChannelRead(req.retain());
        }
    }

    private static final class StaticHandler extends SimpleChannelInboundHandler<FullHttpRequest> {
        private final boolean serveFiles;

        StaticHandler(boolean serveFiles) { this.serveFiles = serveFiles; }

        @Override
        protected void channelRead0(ChannelHandlerContext ctx, FullHttpRequest req) throws IOException {
            String path = req.uri().split("\\?")[0];
            if (path.equals("/")) {
                path = "/index.html";
            }
            byte[] body = null;
            if (serveFiles && !path.contains("..")) {
                try (InputStream in = BridgeServer.class.getResourceAsStream("/web" + path)) {
                    if (in != null) {
                        body = in.readAllBytes();
                    }
                }
            }
            FullHttpResponse res;
            if (body == null) {
                res = new DefaultFullHttpResponse(HttpVersion.HTTP_1_1, HttpResponseStatus.NOT_FOUND);
            } else {
                res = new DefaultFullHttpResponse(HttpVersion.HTTP_1_1, HttpResponseStatus.OK, Unpooled.wrappedBuffer(body));
                res.headers().set(HttpHeaderNames.CONTENT_TYPE, contentType(path));
                res.headers().set(HttpHeaderNames.CACHE_CONTROL, "no-store");
            }
            res.headers().setInt(HttpHeaderNames.CONTENT_LENGTH, res.content().readableBytes());
            ctx.writeAndFlush(res).addListener(ChannelFutureListener.CLOSE);
        }

        private static String contentType(String path) {
            if (path.endsWith(".html")) return "text/html; charset=utf-8";
            if (path.endsWith(".js")) return "text/javascript; charset=utf-8";
            if (path.endsWith(".css")) return "text/css; charset=utf-8";
            return "application/octet-stream";
        }
    }
}
