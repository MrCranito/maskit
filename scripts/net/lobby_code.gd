class_name LobbyCode
extends RefCounted
## Codes de salon : 6 caractères parmi un alphabet sans caractères ambigus (pas de I, L, O,
## 0, 1). Même règle que le serveur (server/relay.js : CODE_ALPHABET, normalizeCode).

const ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const LENGTH := 6


## Saisie du joueur → forme canonique (majuscules, sans espaces ni tirets ni ponctuation).
static func normalize(s: String) -> String:
	var out := ""
	for ch: String in s.to_upper():
		var c := ch.unicode_at(0)
		if (c >= 65 and c <= 90) or (c >= 48 and c <= 57):
			out += ch
	return out


static func is_valid(s: String) -> bool:
	if s.length() != LENGTH:
		return false
	for ch: String in s:
		if not ALPHABET.contains(ch):
			return false
	return true


## Code aléatoire (tests, mode hors ligne) ; le serveur génère les vrais codes.
static func generate(rng: RandomNumberGenerator) -> String:
	var out := ""
	for i: int in LENGTH:
		out += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
	return out


## Affichage aéré : « ABC 123 ».
static func pretty(code: String) -> String:
	if code.length() != LENGTH:
		return code
	return code.substr(0, 3) + " " + code.substr(3, 3)
