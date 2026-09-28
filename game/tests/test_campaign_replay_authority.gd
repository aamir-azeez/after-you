extends "res://tests/test_campaign_recovery_replay.gd"
## Keep authority/pending/terminal checks separate from full collection playback.

func _run() -> void:
	await _authority_changes()
	await _pending_recovery()
	await _terminal_during_bloom()
	print("Campaign replay authority: %d checks, %d failures" % [checks,failures])
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)
