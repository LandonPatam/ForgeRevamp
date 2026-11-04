extends RefCounted
const CoinToss = preload("res://scripts/ui/CoinTossPanel.gd")
## Isolated online path through the exported application; launched by tools/online-app-check.mjs.
var app: Control
var checks: RefCounted
var remote_address := ""
var report_path := ""
func run(root: Control) -> void:
 app = root
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--online-peer="): remote_address = argument.trim_prefix("--online-peer=")
  if argument.begins_with("--online-report="): report_path = argument.trim_prefix("--online-report=")
 app.images.network_enabled = false
 checks = load("res://tests/ApplicationIntegration.gd").new()
 checks.app = app
 if not report_path.is_empty(): checks.capture_root = report_path.get_base_dir()
 checks.deadline = Time.get_ticks_msec() + 240000
 app.api.response.connect(func(id, _op, result): checks.responses[id] = result)
 app.api.failed.connect(func(id, message): checks.errors[id] = message)
 var progress := Timer.new()
 progress.wait_time = 5.0
 app.add_child(progress)
 progress.timeout.connect(func(): print("ONLINE APP STATE: ", app.view, " / ", app.computer.phase if app.computer != null else "startup"); RenderingServer.force_draw())
 progress.start()
 if not await checks.until(func(): return app.startup_done and not app.busy, "startup"): return
 app.computer.set_deck_filter("precon" if remote_address.is_empty() else "custom", false)
 app._select_deck(0)
 if not await checks.until(func(): return app.selected_deck.get("legal", false), "legal precon"): return
 if not remote_address.is_empty():
  await remote_check()
  return
 if not await checks.online_join_check(): return
 print("PASS: exported Mac application online joining, seat token, disk reveal, correct players, leave and cleanup")
 app.get_tree().quit()

func write_report(value: Dictionary) -> void:
 if report_path.is_empty(): return
 var file := FileAccess.open(report_path, FileAccess.WRITE)
 file.store_string(JSON.stringify(value, "  "))

func remote_check() -> void:
 checks.deadline = Time.get_ticks_msec() + 600000
 app.net.join(remote_address, {"name": "Mac test player", "avatar": 2, "portrait": ""}, app.selected_id)
 if not await checks.until(func(): return app.net.is_joined() or not app.net.error.is_empty(), "Windows lobby"): return
 if not checks.check(app.net.is_joined(), "Windows rejected the join: " + app.net.error): return
 write_report({"stage": "lobby", "host": remote_address, "roster": app.net.roster})
 await app.start_game()
 if not await checks.until(func(): return app.net.is_ready() or app.remote_game, "Mac presses PLAY to ready its selected deck"): return
 print("READY: Mac test player has pressed PLAY. The Windows host must ready too.")
 if not await checks.until(func(): return app.view == "game" and not app.busy and app.game != null, "Windows host starts the game"): return
 var driver: RefCounted = load("res://tests/LiveIntegration.gd").new()
 driver.ui = app.game
 var Starting := load("res://scripts/ui/StartingPlayerPanel.gd")
 while Time.get_ticks_msec() < checks.deadline:
  await app.get_tree().create_timer(0.3).timeout
  var state: Dictionary = app.game.snapshot
  if not state.get("connectionReady", false): continue
  if app.game.modal.visible and app.game.modal_panel is CoinToss: continue
  var kind: String = state.get("prompt", {}).get("inputKind", "")
  if int(state.get("game", {}).get("turn", 0)) >= 1 and not state.game.get("mulligan", false) and kind not in ["InputConfirmMulligan", "InputLondonMulligan", "InputSelectEntitiesFromList", "", "InputLockUI"]: break
  if not state.get("asks", []).is_empty(): driver.submit_choice()
  elif kind == "InputConfirmMulligan": app.game.opening_hand.submit("ok")
  elif Starting.needs_selection(state): app.game.modal_panel.buttons[0].pressed.emit()
  elif state.prompt.get("okEnabled", false): app.game._primary_action()
 if not checks.check(Time.get_ticks_msec() < checks.deadline, "Windows opening decisions did not finish"): return
 var session: String = app.game.adapter.session
 app.game.adapter.socket.close()
 await app.get_tree().create_timer(0.5).timeout
 if not await checks.until(func(): return app.game.snapshot.get("connectionReady", false) and app.game.adapter.session == session, "reconnect to the same Windows seat"): return
 var state: Dictionary = app.game.snapshot
 if not checks.check(state.players.size() >= 2 and state.players[0].name == "Mac test player", "Mac controls its own Windows-hosted seat"): return
 for player in state.players.slice(1):
  if not checks.check(player.zones.Hand.all(func(card): return card.get("hidden", false)), "Windows opponent hand remains hidden"): return
 write_report({"stage": "verified", "host": remote_address, "players": state.players.map(func(player): return player.name), "turn": state.game.turn, "phase": state.game.phase, "ownHand": state.players[0].zones.Hand.size(), "opponentHandsHidden": true, "reconnected": true})
 if not report_path.is_empty():
  RenderingServer.force_draw()
  app.get_viewport().get_texture().get_image().save_png(report_path.get_base_dir().path_join("mac-windows-table.png"))
 app.request_end_game()
 app.confirm.confirmed.emit()
 if not await checks.until(func(): return not app.busy and not app.ending_session and app.game == null, "Mac leaves the Windows game"): return
 print("PASS: live Mac-to-Windows lobby, table, opening choices, hidden hands, reconnect and leave")
 app.get_tree().quit()
