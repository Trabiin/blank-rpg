extends RefCounted
## The territory map grows to about 24 provinces in five regions (issue #53).
##
## Saves from before regions only ever had the Act 1 map (the Hollow Marches), so they get the
## starting regions written down as open. Their nine provinces keep their ids, owners and Fray;
## the new provinces are not in the save, so they start as data/provinces.json has them, under the
## fog of their locked regions, when Empire.from_dict() builds the campaign.

static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY:
		return save  # nothing of a campaign to upgrade (the format step fills one in first)
	if typeof(empire.get("regions")) != TYPE_ARRAY:
		empire["regions"] = Empire.starting_regions()
	return save
