**QuickQuesting** is an addon that automatically accepts and turns in quests when you talk to an NPC, so you can fly through quest hubs.

* Accepts available quests and turns in completed ones
    * Works on gossip windows and classic quest greeting lists
* Picks your reward when there is a choice (optional)
* Shares the quests you accept with your party (optional)
* Accepts quests other players share with you (optional)
* Abandons a quest when you click it in the quest log or tracker while holding a modifier key (on by default)

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
    * Applies to the quests you accept, automated or by hand, except those another player shared with you or that you joined from another player's prompt: the party already got that offer
    * One quest at a time per player: nobody's open quest popup is replaced, and a player who is still deciding gets the next quest after answering
    * **Only share with players in your zone** (on by default): a quest is shared only if another party member is in your zone (caves, sub-zones and dungeon floors count as the zone), and only they are waited on. See Auto share
* **Accept quests shared with you** (off by default; ticking the share option above turns it on)
    * Also joins quests another player starts, such as an escort (the "is starting ... Would you like to as well?" prompt)
    * Works without auto share. If you untick it, it stays off until you next tick the share option
    * Your exceptions, the quest scope and the skip key all apply
* **Abandon quests with a modifier click** (on by default)
    * **Hold this key while clicking a quest**: **Shift**, **Ctrl** or **Option / Alt** (default)
    * Works on quests in the quest log and in the objective tracker. See Abandon
* **Exceptions**
    * Quests that are never handled automatically. Add them by quest ID or from your quest log; all managed in the settings panel.

## Skip key
Hold the skip key while talking to an NPC, or when a shared quest or a join prompt pops up, and the addon does nothing, so you can read and handle the quest yourself.

## Abandon
Hold the abandon key and click a quest in the quest log or the objective tracker to abandon it right away, with no confirmation. A chat message links the abandoned quest. This is the former **Quick Abandon** addon, now built in: if you still have it installed, Quick Questing offers to disable it and reload your UI on login (or you can uninstall it), and your old behavior (Alt, enabled) is the default here.

## Auto share
* WoW can only share with the whole party, not one player. The addon reads the game's per-player replies to decide when to share again.
* Players already on a quest get no prompt.
* A quest keeps being shared until every player has accepted or declined it, or can't take it. Declining is final for that player only.
* The trade-off: WoW can't leave anyone out of a share, so when the quest is shared again for someone else, players who declined it are asked again. At most 5 shares per quest.
* A player still deciding on an earlier quest gets this one after answering.
* A player who doesn't answer within 60 seconds no longer holds anything up, and gets the quest once more 3 minutes later, in case they were away. If they answer the first popup before then, that settles it.
* A player who is too far, dead or has a full quest log gets it again once they look able (checked every 30 seconds, for up to 5 minutes).
* With **Only share with players in your zone** on, a quest is shared only while at least one other player is in your zone. If nobody is, it isn't shared, and it isn't shared later when someone arrives. WoW still shows the share to everyone in the party, but players outside your zone never cause it to be shared again. A player who comes into your zone gets the quest with the next share that goes out for someone else.
* Zones are checked each time a quest is about to be shared. If your own zone can't be read, quests are shared as if the option were off. A player whose zone can't be read counts as outside it, except in an instance or a raid when no player's zone can be read.
* Players already on the quest, who completed it, or who aren't eligible (level, class and the like) are not asked again.
* Waits while you are in combat, on a loading screen, or while the game restricts chat for addons (boss encounters, Mythic+, rated PvP). The queue is not kept across `/reload`.
* A quest you accept from another player's share, or join from their prompt, isn't shared again, whether you accepted it automatically or by hand.
* The skip key does not stop sharing.

## Deliberately left alone
* Quests on your exception list
* Turn-ins that cost gold or currency
* Repeatable hand-ins that take items (unless daily or weekly)
* PvP-flagged quests
* Quests started by an item, an area trigger or the adventure map
* Quests shared by other players, and prompts to join a quest another player started, unless **Accept quests shared with you** is on
* Join prompts while your quest log is full, and PvP quests offered through a join prompt
* Non-quest gossip options

## Planned
* Reward choice **More useful for spec** (not implemented yet)
* An option to set a currency preference order, used to pick when a reward choice includes currencies (not implemented yet)

## Options
Esc > Options > AddOns > Quick Questing, or type `/quickquesting` or `/qquest`.
