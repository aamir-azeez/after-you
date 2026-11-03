extends RefCounted
## Icons that mean the same thing on every screen, so one change here reaches
## each place that shows them (tests/test_shared_paths.gd (l) holds the
## leaderboard one to this file).
##
## LEADERBOARD: the Phosphor "trophy" (assets/ui/social, MIT, with its
## LICENSE.txt), the owner's pick for every leaderboard button, row and title
## (2026-11-03). What's new names it "trophy" (presentation/whats_new_kit.gd).
const LEADERBOARD = preload("res://assets/ui/social/trophy.svg")
