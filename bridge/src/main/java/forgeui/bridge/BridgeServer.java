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

/**
 * Local HTTP + WebSocket server. Serves the bundled test page from {@code /web} on the classpath and
 * carries JSON messages on {@code /ws}. Binds to loopback only.
 */
final class BridgeServer {
    private final int port;
    private final ChannelGroup clients = new DefaultChannelGroup(GlobalEventExecutor.INSTANCE);
    private final Consumer<String> onMessage;
    private final Runnable onConnect;
    private EventLoopGroup boss;
    private EventLoopGroup workers;

    BridgeServer(int port, Consumer<String> onMessage, Runnable onConnect) {
        this.port = port;
        this.onMessage = onMessage;
        this.onConnect = onConnect;
    }

    void start() throws InterruptedException {
        boss = new NioEventLoopGroup(1);
        workers = new NioEventLoopGroup(2);
        new ServerBootstrap()
                .group(boss, workers)
                .channel(NioServerSocketChannel.class)
                .childHandler(new ChannelInitializer<SocketChannel>() {
                    @Override
                    protected void initChannel(SocketChannel ch) {
                        ch.pipeline().addLast(new HttpServerCodec());
                        ch.pipeline().addLast(new HttpObjectAggregator(1 << 20));
                        ch.pipeline().addLast(new WebSocketServerProtocolHandler("/ws", null, true, 1 << 22));
                        ch.pipeline().addLast(new StaticHandler());
                        ch.pipeline().addLast(new SocketHandler());
                    }
                })
                .bind(new InetSocketAddress("127.0.0.1", port)).sync();
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
                onConnect.run();
            }
            super.userEventTriggered(ctx, evt);
        }

        @Override
        public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
            ctx.close(); // client went away; nothing to do
        }

        @Override
        protected void channelRead0(ChannelHandlerContext ctx, TextWebSocketFrame frame) {
            try {
                onMessage.accept(frame.text());
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    private static final class StaticHandler extends SimpleChannelInboundHandler<FullHttpRequest> {
        @Override
        protected void channelRead0(ChannelHandlerContext ctx, FullHttpRequest req) throws IOException {
            String path = req.uri().split("\\?")[0];
            if (path.equals("/")) {
                path = "/index.html";
            }
            byte[] body = null;
            if (!path.contains("..")) {
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
