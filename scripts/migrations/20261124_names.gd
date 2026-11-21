extends RefCounted
## Naming pass (issue #158, docs/NAMING.md): names that read as AI-generated were replaced.
## Ids did not change, so nothing in the campaign moves. This step only rewrites the old display names
## inside text a save keeps (journal history, expedition reports, notices), so a long campaign's history
## reads with the new names too.
##
## The list is frozen here on purpose: later renames get their own step.

const RENAMES := [
	["Notary Fennick Marrow", "Notary Fennick"],
	["Quill Marrow", "Edwin Pask"],
	["\\bMarrow(?=('s)?\\b)(?! Broth)", "Fennick"],
	["Brannoc Coil", "Brannoc Tolley"],
	["\\bCoil\\b", "Tolley"],
	["Sister Abeyance", "Sister Hild"],
	["\\bAbeyance\\b", "Hild"],
	["Jessamy Nightjar", "Jessamy Leake"],
	["\\bVelvette\\b", "Fauvette"],
	["Pell Undermoss", "Pell Mossop"],
	["Hesper Quoin", "Hetty Coyne"],
	["\\bHesper\\b", "Hetty"],
	["Dunmore Vell\\b", "Dunmore Vellacott"],
	["Lampwick Hills", "Wickham Hills"],
	["Lampwick hills", "Wickham hills"],
	["\\bLampwick(?=('s)?\\b)", "Wickham"],
	["\\bCandlemere\\b", "Candleford"],
	["Inkmere Shallows", "Pendower Shallows"],
	["Quillpine Pass", "Scarth Pass"],
	["\\bLedgerside\\b", "Ledsham"],
	["Saltgrave Harbour", "Trevail Harbour"],
	["\\bSaltgrave\\b", "Trevail"],
	["Rosewine Terraces", "Vauclair Terraces"],
	["[Tt]he Drowned Light", "Polgarrow Light"],
	["Hollow Marches", "Brack Marches"],
	["Raven's Quill", "Crow Quill"],
]


static func migrate(save: Dictionary) -> Dictionary:
	var res := []
	for r in RENAMES:
		res.append([RegEx.create_from_string(r[0]), r[1]])
	for k in save.keys():
		save[k] = _fix(save[k], res)
	return save


## Rewrites string values only. Dictionary keys and ids (all lower case) are never touched.
static func _fix(v, res: Array):
	match typeof(v):
		TYPE_STRING:
			var s: String = v
			for r in res:
				s = (r[0] as RegEx).sub(s, r[1], true)
			return s
		TYPE_ARRAY:
			for i in v.size():
				v[i] = _fix(v[i], res)
		TYPE_DICTIONARY:
			for k in v.keys():
				v[k] = _fix(v[k], res)
	return v
