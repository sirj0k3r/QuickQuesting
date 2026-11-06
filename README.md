**QuickQuesting** is an addon that automatically accepts and turns in quests when you talk to an NPC, so you can fly through quest hubs.

* Accepts available quests and turns in completed ones
    * Works on gossip windows and classic quest greeting lists
* Picks your reward when there is a choice (optional)
* Shares the quests you accept with your party (optional)
* Accepts quests other players share with you (optional)

## Settings
* **When a turn-in offers a reward choice**
    * **Nothing**: leaves the reward window open for you to choose (default)
    * **Highest sell price**: takes the reward that sells for the most; if nothing has a sell price it takes the first reward. If a choice is a currency, the window stays open for you
* **Which quests to handle**
    * **All quests** (default) or **Repeatable quests only**
        * Daily, weekly and other repeatable quests
* **Hold this key to skip automation**
    * **Shift** (default), **Ctrl** or **Option / Alt**
* **Share quests you accept with your party** (off by default)
    * Applies to the quests you accept, automated or by hand, except those another player shared with you: the party already got that offer
    * One quest at a time per player: nobody's open quest popup is replaced, and a player who is still deciding gets the next quest after answering
* **Accept quests shared with you** (off by default; ticking the share option above turns it on)
    * Works without auto share. If you untick it, it stays off until you next tick the share option
    * Your exceptions, the quest scope and the skip key all apply
* **Exceptions**
    * Quests that are never handled automatically. Add them by quest ID or from your quest log; all managed in the settings panel.

## Skip key
Hold the skip key while talking to an NPC, or when a shared quest pops up, and the addon does nothing, so you can read and handle the quest yourself.

## Auto share
* WoW can only share with the whole party, not one player. The addon reads the game's per-player replies to decide when to share again.
* Players already on a quest get no prompt.
* Once any player declines a quest, it isn't shared again this session, so nobody gets asked twice. The trade-off: a slower player who was still busy with an earlier quest misses that one. Later quests are still offered to everyone.
* A player who doesn't answer within 60 seconds no longer holds anything up.
* Waits while you are in combat, on a loading screen, or while the game restricts chat for addons (boss encounters, Mythic+, rated PvP). The queue is not kept across `/reload`.
* A quest you accept from another player's share isn't shared again, whether you accepted it automatically or by hand.
* The skip key does not stop sharing.

## Deliberately left alone
* Quests on your exception list
* Turn-ins that cost gold or currency
* Repeatable hand-ins that take items (unless daily or weekly)
* PvP-flagged quests
* Quests started by an item, an area trigger or the adventure map
* Quests shared by other players, unless **Accept quests shared with you** is on
* Prompts to join a quest another player started, such as an escort
* Non-quest gossip options

## Planned
* Reward choice **More useful for spec** (not implemented yet)
* An option to set a currency preference order, used to pick when a reward choice includes currencies (not implemented yet)

## Options
Esc > Options > AddOns > Quick Questing, or type `/quickquesting` or `/qquest`.
