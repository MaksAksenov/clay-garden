extends RefCounted
## Star thresholds and the bot's goal — the single source.
## Interface: ★ 60% of the ideal, ★★ 80%, ★★★ floor(92%) (but no higher than ideal−1), "Perfect" — a crown for the solver's ideal.
## 92% was chosen from real data (stage 3): at 95% the player would have got ★★★ on 2 of their 9 levels, at 90% — on 7.
## The difficulty metric (G) is computed not from the interface thresholds but from its own goal: ideal − floor(ideal/40).
## So changing the player's thresholds doesn't affect D.


static func thresholds(perfect: int) -> Array:
	var top := mini(perfect - 1, int(floor(perfect * 0.92)))
	return [int(round(perfect * 0.6)), int(round(perfect * 0.8)), maxi(1, top)]


static func count(score: int, perfect: int) -> int:
	var n := 0
	for t in thresholds(perfect):
		if score >= t:
			n += 1
	return n


static func metric_target(perfect: int) -> int:
	return perfect - perfect / 40
