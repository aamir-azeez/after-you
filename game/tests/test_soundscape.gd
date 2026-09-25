extends SceneTree

class Probe:
	extends "res://services/soundscape.gd"
	var pulses: Array[int] = []
	func _emit_haptic(duration_ms: int) -> void:
		pulses.append(duration_ms)

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _run() -> void:
	var sound := Probe.new()
	sound.configure({"sound":false,"haptics":true})
	root.add_child(sound)
	await process_frame
	_check(not sound.ambience.playing,"Saved mute is respected before the audio node enters the tree")
	sound.play_footstep()
	_check(sound.next_step==0,"Saved mute also suppresses walking sounds")
	sound.play_reunion()
	_check(not sound.reunion_voice.playing,"Saved mute suppresses reunion sound")
	_check(is_equal_approx(sound.REUNION.get_length(),0.65),"Reunion uses the single approved greeting, not the repeated audition")
	var bed := sound.ambience.stream as AudioStreamWAV
	_check(bed.loop_end==roundi(bed.get_length()*bed.mix_rate),"Imported compressed audio loops across its full duration")
	_check(bed.loop_end>=bed.mix_rate*15,"The ambient loop is not truncated to encoded-byte length")
	sound.consume_events(["seed_caught"],true)
	_check(sound.next_voice==0 and sound.pulses==[35],"Haptic catch feedback works independently of sound mute")
	sound.pulses.clear()
	sound.configure({"sound":true,"haptics":false})
	_check(sound.ambience.playing,"Enabling sound starts ambience")
	sound.play_reunion()
	_check(sound.reunion_voice.playing and sound.pulses.is_empty(),"Reunion plays independently without adding vibration")
	sound.play_footstep()
	var first_step: AudioStream = sound.step_voices[0].stream
	sound.play_footstep()
	_check(sound.next_step == 2 and sound.step_voices[0].playing and sound.step_voices[1].playing, "Simultaneous player and ghost contacts remain independently audible")
	_check(sound.step_voices[1].stream != first_step, "Overlapping contacts retain the alternating sound variants")
	sound.play_footstep()
	_check(sound.next_step == 3 and sound.step_voices.size() == 3 and sound.step_voices[2].playing and sound.step_voices[2].stream == first_step, "The third contact is not rate-limited or coalesced")
	_check(sound.step_voices[0].volume_db == -23.0 and sound.step_voices[0].stream.get_length() <= 0.11, "The original overlapping mix uses the short revised clips")
	sound.consume_events(["seed_caught","island_bloomed"],true)
	_check(sound.next_voice==2 and sound.pulses.is_empty(),"Disabling haptics leaves audible gameplay feedback enabled")
	sound.configure({"sound":true,"haptics":true})
	sound.consume_events(["seed_caught","island_bloomed"],false)
	_check(sound.next_voice==4 and sound.pulses.is_empty(),"Replay events play sound without vibrating the device")
	sound.set_backgrounded(true)
	_check(not sound.reunion_voice.playing,"Backgrounding stops an in-flight reunion")
	sound.play_reunion()
	_check(not sound.reunion_voice.playing,"Background suppresses new reunion audio")
	_check(not sound.ambience.playing,"Backgrounding stops ambience")
	var all_stopped := true
	for voice in sound.voices:
		all_stopped=all_stopped and not voice.playing
	_check(all_stopped,"Backgrounding stops in-flight effects")
	sound.play_footstep()
	_check(sound.next_step==3 and not sound.step_voices[0].playing and not sound.step_voices[1].playing and not sound.step_voices[2].playing,"Backgrounding stops and suppresses every overlapping walking sound")
	var before := sound.next_voice
	sound.consume_events(["seed_caught","island_bloomed"],true)
	_check(sound.next_voice==before and sound.pulses.is_empty(),"Background events cause neither audio nor vibration")
	sound.set_backgrounded(false)
	_check(sound.ambience.playing,"Returning foreground resumes allowed ambience")
	sound.play_reunion()
	_check(sound.reunion_voice.playing,"A new foreground reunion plays immediately")
	sound.stop_reunion()
	_check(not sound.reunion_voice.playing and sound.ambience.playing,"Pausing a reunion leaves the ambience preference alone")
	sound.play_reunion()
	sound.play_footstep()
	_check(sound.next_step == 4, "Returning foreground permits a new contact immediately")
	sound.configure({"sound":false,"haptics":false})
	_check(not sound.reunion_voice.playing,"Turning sound off stops an in-flight reunion")
	sound.set_backgrounded(true)
	sound.set_backgrounded(false)
	_check(not sound.ambience.playing,"Returning foreground preserves the saved mute setting")
	sound.consume_events(["unknown_event"],true)
	_check(sound.next_voice==before and sound.pulses.is_empty(),"Unrecognized simulation events remain silent")
	sound.queue_free()
	await process_frame
	# Let the audio thread consume its queued stop commands before shutting down.
	await create_timer(0.15).timeout
	print("AFTER YOU SOUNDSCAPE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
