# Drunken Vikings: Design

*Status: agreed in broad lines; we build region 1 first (section 4), as a playable slice, before the other regions. The rowing experiment and the first level (one lake system, following a longship) work.*

**Drunken Vikings is an open-world trading game for girls of about seven to twelve (and everybody who likes the same things), played by rowing in front of a webcam: every stroke is a crunch, so you train your abs while you trade.**
You are a young viking trader (Ylva, unless you give yourself another name) with a small rowing boat and a few pieces of silver.
You row across a land of lakes, rivers and, later, the sea, carry goods from where they are cheap to where they are wanted, take on missions for the people of the settlements, and hear the news (and get quick offers) from the boats you meet.
With the silver, you buy boosters, improve your boat and your looks, build up your own farm (animals, fields, land), and buy bigger ships.

Nobody fights. You win by being clever, quick and well informed.
One or two players play **together**, in the same boat.

# Game design

## 1. Pillars

1. **The rowing is the controller.** Each stroke (lean back and pull, lean forward and reach) pushes the boat, which glides on; going sideways with the head steers it while it glides (see section 9). Row a few strokes, glide and steer, row again.
2. **Trading, not fighting.** Like the space trading games (*Elite*, *Privateer*, *Frontier: First Encounters*) and their peaceful cousins on the water (*Sailwind*) and on the road (*Euro Truck Simulator 2*): buy low, sell high, take on jobs, grow your ship. The dangers are the wind, the weather, the shallows, the current, and running out of time, never people.
3. **The world talks to you.** Boats sail across the lakes on their own errands; row up beside one and its people tell you the news, a good deal or a bad price, or make you a quick offer (section 6). Knowing more than the others is how a trader wins.
4. **A farm to come home to.** The players own a small farm at home: they buy animals, bring them feed, sell what the farm makes, and buy land to grow it (section 7). Every trip has a reason to come home.
5. **Short trips with a clear end.** A session is one or two trips of about ten minutes, which end in a port, where the game saves. The open world never pulls you on: no daily rewards, no timers which run while you are away, no loot boxes (see the manifesto). Nothing happens while the game is off: the days pass only on the trips.
6. **Stars and things, not statistics.** After a trip we show the silver you made, what you bought and the stars of a mission, never the number of crunches or calories.
7. **Together in one boat.** With two players, both row the same boat: rowing in time makes it fly (section 9). They share the silver, the cargo and the homestead.
8. **Offline and private**, like our other games. The webcam images stay in memory and never leave the computer.

## 1a. The modes

* **Party mode** (for the smaller children): the players row behind the **wedding longship** (garlands of flowers, the bride and the groom at the stern), from their farm to the market village. The wedding party drops flower wreaths, ribbons, honey cakes and apples into the water; every one the players pick up (by rowing over it) gives a silver coin, into the purse of their voyage. There is nothing else to do and nothing to lose: just row, steer and pick up.
* **Chase mode**: the pirates hunt the players, who must row from one settlement to another (800 to 1800 m along the water) before the pirate longship catches them. The pirates find their way around the islands, set out a few seconds after the players, and row a little slower than players who keep rowing: who keeps rowing makes it, who stops for long is caught. Nobody is hurt: the pirates who catch the players only laugh, kiss the prow of their boat and sail away, and the players try again; the players who make it get 10 silver, and the people of the town chase the pirates away. Arrows at the edges of the screen show the way to the town and where the pirates are, and the edges glow red as the pirates come closer.
* **Practical mode**: the open world of trading and the farm (sections 4 to 10).

The start screen asks how many row (one, or two with an oar each) and which mode to play; the practical mode goes on with the saved voyage, or starts a new one. The silver of the party and of the chase goes into the purse of the voyage.

## 2. Setting

The **Lakeland**, a made-up land of lakes and rivers in the north, around the year 900.
It is inspired by the lakes of Sweden (Mälaren, Hjälmaren, Vänern) and by the life of the time, but its places and its people are our own, with names made up from Norse-sounding parts (`dev/maps/make_lakes.py`), so that no real place or person is meant.

* **The lakes** are joined by narrow sounds, short rivers (with a current, upstream is harder) and a few **portages**, where the boat is dragged over land on logs (a short scene in which the players "pull": a few deep strokes).
* **The sea** (the eastern sea, the Baltic of our world) opens only later in the game, with the bigger ships (section 8).
* **The settlements** are farms, inns by the sounds (where the boats stop, and which buy ale and mead), fishing villages, market towns, a trading place on an island (the biggest market), a smithy village by the iron bogs, a hunters' camp in the north, a monastery-like house of learning far in the south (late game), and the players' own homestead.
* **The season** goes from spring to autumn over the game; the last missions bring in the winter stores before the lakes freeze.

### Tone

* Vikings in this game are farmers, traders, craftspeople and explorers, which most of them were. There are no raids, no slaves and no weapons in use; a sword may hang on a wall.
* Women trade, own boats and lead households, as they could at the time. The hero is a woman; the crew and the people in the settlements are mixed.
* "Drunken" in the title is both: the zig-zag of a boat whose rowers are not yet in time (section 9), and the ale and the mead of the time. Ale, mead and (rare, from far away) wine are goods like any other: the inns, the weddings and the feasts buy them, and a few missions bring the ale to a wedding or the mead to a feast. The feasts are merry, with songs and a tipsy uncle, but nobody is hurt and nobody is mocked.
* Fun facts after missions tell real things about the time: the silver from far away, the runestones, the combs of antler, the iron from the bogs.

## 3. Characters

* **Ylva** (player 1, by default) and **Sigrid**, her cousin (player 2, by default), young traders with a small boat. The players choose the name, the looks and the clothes (section 7).
  * **The looks of the rowers** (done): when a new journey starts (and later with the card "Your vikings" on the choice of what to play), each rower chooses a viking girl (Ylva's braids and dress) or a viking boy (tousled hair, a tunic over trousers), and the colour of the skin (5), of the hair (5) and of the clothes (5); each card shows the rower in the boat as the card would make them look. The look is saved with the journey; the rowers in the boat and the dress-up in the camera picture show it (`Looks`, `scenes/looks/`).
* **The pet in the boat**: at the start, the players choose a kitten, a puppy or a little goat, and name it. It rides in the bow, reacts to what happens (it purrs at a good deal, hides from the rain, barks at the geese), and helps in some missions (the puppy finds the lost lamb, the kitten the mice in the grain store).
* **Tova the healer**, a young herbalist on the island of the home lakes, who teaches the players to look after sick animals: which herb helps which animal, where the herbs grow, and how to keep the animals warm, fed and calm. The players become her helpers, and later healers themselves.
* **Grandmother Åsa** at the homestead: she gives the first missions, explains the trading and keeps the homestead while the players are away.
* **The people of the settlements**: the market wardens, the smith, the weavers, the fishers, the hunters, the boatwright, the runecarver, the herbalist, the children. They give missions and buy and sell.
* **The skippers of the boats on the lakes** (section 6): each with a name, a boat, a route and a way of talking (the chatty fisher, the grumpy salt trader, the messenger who is always late, the children in a canoe, the old ferryman who knows every legend).
* **The rivals** are other traders who race you to a good deal; they never cheat or harm, they are just quick. Beating a rival to a market gives a better price.

## 4. The world

### The regions

The world opens region by region, each with its own lakes, settlements, goods and boats on the water. A region opens with a mission (and, for the sea, a ship which can sail there).

| # | Region | Waters | New |
|---|---|---|---|
| 1 | **Home Lakes** | Four small lakes and their sounds around the homestead | Rowing, trading, the first missions |
| 2 | **The Long Lake** | One long lake with many islands and the island market | The big market, the rivals, the news from boats |
| 3 | **The Iron River** | A river up to the bog lakes of the smiths | The current, the portages, iron |
| 4 | **The Northern Waters** | Cold lakes, fog, the hunters' camps | Fog, furs and antler |
| 5 | **The Skerries and the Sea** | The coast, the skerries, the open sea | Waves, wind, the knarr and its sail |

Each region is made by the generator from its own seed, by hand tweaked where a mission needs it, and stored in `data/world/`.

### Distances and time

* A leg between two neighbouring settlements takes **1 to 2 minutes** of rowing; a trip of a mission has about five legs.
* The **days** pass with the distance rowed and the nights in port; prices recover and news grow old with the days (section 5). The day is shown by the light (morning, noon, evening) and ends in a port.

## 5. Trading

### The goods

About 16 goods, each with a picture and a short story, e.g.:

| Good | Made in | Wanted in |
|---|---|---|
| Dried fish | Fishing villages | Inland farms, the hunters |
| Salt | The island market (from far away) | Fishing villages (to dry the fish), everywhere in autumn |
| Iron bars | The smiths by the bogs | The boatwright, the farms |
| Furs | The hunters' camps in the north | The island market |
| Antler combs | The combmaker's village | The market towns |
| Wool and cloth | The farms and the weavers | The north, the hunters |
| Honey | The farms with bees | The mead makers, the markets |
| Ale | The farms with barley, the brewers | The inns, the weddings, the feasts |
| Mead | The mead makers (from honey) | The feasts, the chieftain's hall, the inns |
| Wine | The island market (rare, from the far south) | The chieftain, the rich weddings |
| Soapstone pots | The northern quarries | Everywhere |
| Amber | The sea coast | The island market, the jewellers |
| Glass beads | The island market (from far away) | Everywhere, but little |
| Grain | The farms | The towns, the north |
| Timber and tar | The forest villages | The boatwright, the sea coast |
| Walrus ivory, silver, spices | Only late, from the sea traders | The rich towns |

### Prices

* Every settlement **makes** a few goods (cheap there) and **wants** a few (dear there). The rest sells at the middle price, or not at all.
* **Selling much lowers the price** there, buying much raises it; the prices go back to normal over a few days. So the same trade does not pay twice in a row: the players have to look for new deals (which keeps it from becoming a grind).
* **Events** change the prices for a while: a feast or a wedding (ale and mead are wanted), a good catch (fish are cheap), a late frost (grain is dear), a market day on the island (everything sells better). The events are what the boats on the lakes talk about (section 6).
* The **money** is silver, counted in pieces (the hacksilver of the time, weighed on the trader's scales: a fun little animation).
* **The hold** of the boat limits the cargo (the small boat carries 4 crates; section 8).
* The market screen is simple for children: the goods with pictures, the price as a number and an arrow (cheap here, dear here, as usual), buy and sell with big buttons for the hand cursor. A **price book** remembers the prices which the players saw, with the day they saw them.

## 6. The boats on the lakes

NPC boats sail across the lakes on their own errands, along routes between the settlements: fishers, traders, messengers, ferries, children in canoes, a boat full of goats.

* **Hailing:** row up close to a boat (within about 40 m) and slow down beside it. Its skipper calls over: a speech bubble with a portrait, a short line and a picture (a good with an arrow, a place on the minimap).
* **What they tell:**
  * **Good deals:** "They pay 12 silver for salt in Ravnvik, the fishers there have a great catch!"
  * **Bad prices:** "Don't bring furs to the island market, the hunters just sold a boatload."
  * **News of events:** "Midsummer feast in Torstad in three days!" (mead and honey are wanted there)
  * **Missions:** "The smith in Järnby is looking for someone with a fast boat." (a mission marker appears)
  * **Warnings:** "Fog in the north tomorrow", "The river runs fast after the rain".
  * **Gossip and fun facts** of the time, and now and then a joke.
* **Quick offers:** some skippers trade right there on the water, a few crates at a time, with big buttons in the speech bubble:
  * "I have 3 crates of dried fish, 4 silver each, cheaper than any market. Want them?"
  * "You carry salt? I give 9 silver a crate for 2 crates, right now."
  * "Swap my honey for your wool?"
  * "Take this sheep to my sister in Ravnvik and she gives you 10 silver." (a small delivery on the spot)

  An offer stands only while the boats are side by side: row on, and it is gone. Many offers are good, some are only fair; the price book (section 5) tells which. The quick trades never cheat the players, and they never need a market screen: one picture, one price, yes or no.
* **The news can grow old.** A tip is true when it is told, but other traders hear it too: the longer you wait, the less it pays. The news log shows how old each tip is.
* **Some skippers know more** than others: the messenger knows the events, the fishers the fish and the salt, the old ferryman the legends and the hidden coves. Players learn whom to ask.
* **Helping a skipper** (towing a boat whose oar broke, bringing back a lost net, guiding the children's canoe home) makes them friends: friends give better tips and sometimes a small gift.
* The boats follow the same rules of the water as the players: they slide along the shores, they give way, and they never bump into the players.
* Every bit of news goes into the **news log**, one button away, with the place marked on the map.

## 7. What the silver buys

* **Boosters** for one trip (bought at the markets, as in Bird Dog): honey cakes (stronger strokes), a lucky charm against fog, a good-wind feather, a guide who shows the shortcut, a fish trap which catches dried fish while rowing.
* **Boat improvements** (at the boatwright): a smoother hull (longer glide), better oars (stronger strokes), a sharper rudder (quicker turns), a bigger hold (more crates), a tarp (the goods stay dry in the rain), a lantern (for the fog).
* **Looks:** the clothes, the hair, the braids and the brooches of the players' vikings; the painting of the boat, the stem post (a dragon, a snake, a horse), the sail stripes, the shields along the side for the longship (for show only), a pennant.
* **The farm** (section 7a).
* **Bigger ships** (section 8).

**The balance.** Not everything can be bought after a few missions, nor should the shipyard stay out of reach: the missions pay twice what they did at first (2174 silver in all), so that a child who does the missions one after the other, trading only when short of silver, gets the færing after about 30 missions (some 7 hours of play), the karve after about 65 and the knarr near the end; the longship and the last plots are the goal of those who also trade or grow the farm (who get everything after about 27 hours). Pure trading still pays, but no better than the missions. `dev/balance/balance.gd` plays the rules with bots of these strategies and reports it (see CONTRIBUTING.md).

## 7a. The farm

The players' farm lies on the shore of the home lakes, with its own jetty. Grandmother Åsa keeps it while they are away, and every time they row home, they see it and run it with the hand cursor (a short, calm screen between the trips).

### The animals

| Animal | Costs | Eats (per day) | Gives | Young (a pair, fed, with room) | Sells for |
|---|---|---|---|---|---|
| Hens | little | A little grain | Eggs | A chick every 3 days | little |
| Sheep | some | Hay | Wool, a little milk | A lamb every 4 days | some |
| Goats | some | Hay | Milk | A kid every 4 days | some |
| Pigs | some | Grain and scraps | Piglets | | some |
| Cows | much | Much hay | Much milk | A calf every 6 days | much |
| Bees (hives) | some | Nothing (flowers) | Honey, wax | None | some |
| A horse | very much | Hay and oats | Pulls the plough (bigger fields) | | much |

(The pigs and the horse are not in the game yet.)

* The players **buy** the animals at the markets and the farms of the lakes, and bring them home by boat (a goat in the boat takes the place of a crate, and bleats).
* The animals **need feed**: hay and grain, from the farm's own fields or bought and brought by boat. The farm's store shows how many days the feed lasts.
* **Without feed, no animal dies or suffers harm.** It only stops giving (no eggs, no milk) and looks sad, until the players bring feed; Grandmother Åsa reminds them gently. (The game is for children: no animal ever comes to harm.)
* The animals **give goods** every day of the trips (eggs, wool, milk, honey), which wait in the farm's store; the players take them on the next trip and sell them, or use them for missions.
* **Milk becomes cheese.** The cellar keeps 2 crates of milk; overnight, Grandmother Åsa makes cheese of the milk beyond that, a crate of cheese from 2 crates of milk. So the players find some fresh milk in the store every morning (a little money, sold near home), and the rest waits as cheese (the same silver in half the room of the hold, and it keeps). There is no chance in it: the more cows and goats, the more cheese.
* **The young come steadily, never faster and faster.** A pair of a kind (or more) has one young every few days (the table), however big the herd: 2 hens and 20 hens have the same chicks. A herd which grows by itself would make the farm a money machine and the game too easy; a steady young is a gift to look forward to ("a lamb in 2 days!"). The days count only when
  * the **whole herd ate its fill** that day (too little hay for all the sheep: no day towards a lamb), and
  * the farm has **room** for one more (a full pasture: no young until the players buy land or sell some animals).

  Otherwise the count waits, and goes on when the herd is fed and has room again; nothing is lost and no animal comes to harm. One animal alone has no young, nor have the bees. The farm screen, the morning and the skippers tell the players why: "The sheep are hungry, so no lambs: bring hay!", "No room for lambs and chicks: buy land!", and in the morning "New on the farm: a lamb!".
* A young is at once one more animal of the farm: it takes its room, eats and gives like the others, and can be **sold** where such animals are dealt in (they go to other farms, never to the butcher in the game).
* The players can **sell** their animals where such animals are dealt in (the screen "Animals"), from the boat or fetched from the farm, for half their price (to other farms, never to the butcher): a full pasture never keeps a mission which asks for more animals from being done.

### The land

* The farm starts small: a house, a meadow, a small field, the jetty.
* The players **buy land** from the neighbours, plot by plot (a map of the farm with the plots to buy): more meadow (more animals), more fields (more hay and grain, so less feed to buy), a forest plot (timber for the buildings), a lake shore plot (a fish trap).
* **The fields**: the players plant a crop on a field (seed bought at the markets: barley, flax, turnips, peas, or flowers for the weddings), and it grows over the days of the trips. Each crop takes some days to ripen, and then must be **harvested in time**, within a few days: the farm screen, Grandmother Åsa and the skippers on the lakes remind the players ("The barley is ripe in 2 days; bring it in within 3 days after"), and the warning shows on the map while they row. A late harvest is smaller (the birds ate some), never lost. The harvest goes into the farm's store: feed for the animals, goods to sell, or seed for the next planting. Bigger fields (bought land) and the horse with the plough give bigger harvests.
* **Buildings** go up step by step, each bought with silver and goods (timber, iron, tar): the longhouse grows, a barn (more feed stored), a sheepfold, a henhouse, a boathouse (room for a bigger ship), a loom house (wool becomes cloth, which sells better), a smithy, a sauna, a garden, a runestone with the players' names, and at the end a feast hall.
* **Farmhands** (hired with silver) look after more animals and fields; without them, the farm can only grow so far.

### Why the farm matters

* It gives the trading a purpose: the players trade to grow the farm, and the farm gives them goods to trade.
* It ties the trips together: bring feed home, take the wool to the market, buy a cow on the way back.
* It is the end of the game: the last mission is the autumn feast at the farm, with the friends from all the lakes.

## 8. Ships

**Signe the shipwright** builds ships in her shipyard in Ekvik, the fishing village where the tar comes from (the card "Shipyard" in its port; the skippers on the lakes tell of her). As in Bird Dog, a ship is bought once for very much silver and kept: the players may take any of their ships in the shipyard for free, if their cargo fits in its hold. A ship changes how the boat rows (`data/ships/ships.json`, `Ships`):

| Ship | Price | Hold | Crew | Stroke | Glide | Turns | Top speed |
|---|---|---|---|---|---|---|---|
| **Rowing boat** (the start) | | 4 | | 100% | 100% | 100% | 100% |
| **Færing** (a light four-oared boat) | 80 | 8 | 2 | 120% | 115% | 95% | 115% |
| **Karve** (a small ship with a square sail) | 220 | 16 | 6 | 135% | 145% | 80% | 130% |
| **Knarr** (the wide trading ship) | 450 | 40 | 4 | 100% | 170% | 60% | 115% |
| **Longship** (the fastest) | 800 | 20 | 20 | 170% | 150% | 90% | 160% |

* **The crew rows with the players.** Each stroke of the players is the beat for the whole crew: their oars swing with the players' oars, so a stroke of a bigger ship pushes more, and the sail keeps it gliding longer. So the exercise never stops mattering: without strokes, every ship slows down.
* **The players row on the stern bench** of a bigger ship (their own oars still follow their bodies), with the crew on the benches before them; the bow of a ship stays on the water (it slides along the shores like the small boat).
* **Each ship is painted** (hull, crew, oars, sail and the knarr's cargo); `ships.json` places the parts on the hull picture ("drawn", see `Longship.look`). Signe's slipway, with a ship half built, and her timber stand on the shore of Ekvik.
* **The boatwright's crates** (Bjarne, in the missions) widen whatever ship the players row: they go with the players from ship to ship.
* A big hold shows on the HUD as one crate for each kind of cargo, with how many, and how full the hold is.
* Later: the crew is paid a little silver per trip, the sail needs the wind, and the small boat fits the narrow rivers where the knarr does not.

## 9. Rowing and steering

* **A stroke** is a crunch: lean back and pull the oars to the belly, then lean forward and reach out. The vision counts a stroke when the head goes down and back up by a quarter of the shoulder width (see `RowingMeter`).
* **The boat glides**: each stroke pushes it, and it slows down over several seconds. Row a few strokes, then glide and steer.
* **Steering alone**: go to the side with the head (and the whole upper body); the boat turns to that side, the farther the harder. While steering, no strokes count, so the player either rows or steers.
* **The land never hurts**: the boat slides along the shores instead of stopping, as in Bird Dog.
* **Two players** sit in the same boat, each in their half of the camera picture, and each pulls the oar on their side: the player on the left of the (mirrored) picture the left oar, the other the right oar. Nobody steers with the head: **the boat turns away from the stronger rower**, as a real boat does. Each stroke pushes the boat and kicks its bow away from the side of the stroke; strokes in time cancel the kicks, strokes out of time make the boat wobble (the zig-zag of drunken vikings), and a rower who pulls more often or deeper turns the boat. **Rowing in time** (strokes within half a second of each other) gives a bonus of a third, shown by the oars flashing gold, so that the players count together ("one, two, pull!").
* **The rhythm drum**: a booster (or the crew's drummer on the bigger ships) beats a rhythm; strokes on the beat push more. It teaches a steady, healthy pace.
* **Choosing on the screens.** The screens (the start, the ports, the quick offers, the farm) are run with the hands, as in our other games, never with the keyboard: every raised hand moves its own cursor (a small viking glove; a hand detector finds the hands while a screen shows), the buttons are **sticky** (a cursor on a card is drawn to its middle and leaves only when the hand moves clearly beyond its edge), and **holding the cursor still on a card for 2 s** fills a ring around it and chooses it. Behind the screen, the players see themselves dimly, mirrored, so that the hand lies under the cursor. The screens are calm, with few and big cards, and give the players a rest between the legs of rowing.

## 10. Missions

There are **100 missions**, made from a few kinds of building blocks (as in Bird Dog), with their own stories, people and places. They unlock in order within a region, and a few side missions unlock along the way. About 20 missions per region.

### What the missions are about

The game is for **girls of seven to twelve**. The missions are about what they love: **animals** (caring for them, healing them, the newborn foals and lambs, a pet of their own, horses), **friendship** (helping a friend, making new ones on every lake), **celebrations** (weddings, midsummer, the harvest feast, with dresses, flowers, music and ale), **making beautiful things** (dyes, cloth, brooches, amber necklaces, decorating the boat and the farm), **small mysteries** (who takes the honey? where did the kitten go?) and **being clever and brave** (guiding a boat through the fog, finding the hidden cove). Nobody is ever hurt, and **no animal ever dies**: a sick animal waits patiently for its medicine, and gets well when it comes.

### The kinds of missions

| Kind | What the players do |
|---|---|
| **Heal** | An animal is sick: find out what it needs (Tova knows, or the skippers), fetch the herbs or the medicine, and bring it in time. The animal gets well, and the family is happy. |
| **Care** | Help with the newborn: bring blankets and warm milk for the lambs in a cold night, fetch the midwife for a mare which is about to foal, bring hay for a farm whose barn burned down. |
| **Deliver** | Bring goods or a letter to a place, often before a day: the ale for the wedding, the flowers for the bride's crown, the mead for the midsummer feast. |
| **Fetch** | Buy or collect goods from several places and bring them home: the dyes for the wedding dress, the amber for a necklace. |
| **Ferry** | Take a passenger: the bride to her wedding, the healer to a sick foal, a grandmother to see her new grandchild, a runaway goat home. |
| **Follow** | Follow a boat without being left behind (the first level: follow the longship). |
| **Race** | Be the first at the market with the new honey; the rival traders race too (friendly rivals, who become friends). |
| **Find** | Ask the boats and the people until you know where something or someone is: a lost kitten, a lamb which wandered off, a girl who rowed off to see the world. |
| **Rescue** | Save someone in a fix: a swan tangled in a net, a foal stuck in the mud, a skipper whose oar broke, a boat lost in the fog. |
| **Explore** | Map a lake no one has mapped, find the island of the wild horses, the hidden cove from Grandmother's story. |
| **Build** | Bring the timber, the iron and the tar for a new stable, a jetty, a bridge; the players see it grow. |
| **Make** | Bring what a craftswoman needs to make something beautiful (dyes, wool, amber, silver), and get it as a reward: a dress, a brooch, a painted sail. |

### How the missions work

The people of the lakes offer the missions in their ports (the card "Tasks"; Grandmother Åsa's board at home tells where the others wait, and the skippers on the lakes say who looks for help). A mission unlocks when the missions it requires are done; the players carry out **at most three at a time**. A mission is a list of steps, done one after the other (`scenes/game/missions.gd`):

| Step | What the players do |
|---|---|
| **visit** | Dock at a place (talk to someone). |
| **carry** | Take the items of the mission (a passenger, a letter, barrels of wedding ale, logs, a lamb) at one place and bring them to another. |
| **deliver** | Bring goods or animals which the players buy or make themselves (3 crates of salt, 2 goats); at home, they go into the store and onto the farm. |
| **pay** | Pay silver at a place (the weaver's clasp, the boatwright's wages). |
| **hail** | Hail a skipper on the lakes (a given one, or any). |
| **have**, **plant** | Have so many animals on the farm; plant a crop. |

Any step may wait some nights after the step before (the cloth is woven overnight, the horse rests a night).

**The hold.** Every item of a mission takes the room of a crate in the boat, like the goods and the animals. When the boat is full, it takes what fits, and the rest waits at the jetty for the next trip; the players make room by selling, or by unloading at home (the items of the missions stay in the boat). So the hold matters: a small boat (4 crates) takes the six logs of the stable in two trips, and five missions make it bigger (to 5, 6, 8, 10 and 12 crates), for the hauls of the second year (twelve baskets of apples, twelve crates of grain for the north).

**Where to go.** The HUD lists the missions under way with what to do next ("Bring 3 barrels of wedding ale to Mjödkvarn"), the minimap rings the places where they lead, and when such a place is off the screen, a golden arrow on a ring around the middle of the screen points to it, with its name and the mission (arrows which point nearly the same way become one). The key **C** shows the map of the whole region (`WorldChart`), with all the names, the gold rings of the missions and the boats; the game waits until C (or Esc) closes it.

### The 100 missions

For now, all of them play on the Home Lakes, over two years: the first (1 to 50) from the old boat to the first snow, the second (51 to 100) from the breaking of the ice, through the players becoming healers, to the feast at the farm. They move to their regions as the regions are built.

| # | Title | Kind | Given by |
|---|---|---|---|
| 1 | The Old Boat | Visit | Grandmother Åsa, Rimgården |
| 2 | A Pet of My Own | Ferry | Freya and Liv, Kråkhamn |
| 3 | Eggs for the Inn | Deliver | Grandmother Åsa, Rimgården |
| 4 | The Sneezing Sheep | Heal | Grandmother Åsa, Rimgården |
| 5 | News on the Water | Find | Grandmother Åsa, Rimgården |
| 6 | Two Goats for the Farm | Fetch | Grandmother Åsa, Rimgården |
| 7 | The Swan in the Net | Rescue | Old Grim of Svanetorp, Svanetorp |
| 8 | Ale for the Wedding | Deliver | Astrid of the mill, Mjödkvarn |
| 9 | Flowers for the Bride | Fetch | Astrid of the mill, Mjödkvarn |
| 10 | A Bigger Hold | Build | Bjarne the boatwright, Kråkhamn |
| 11 | The Lambs in the Cold Night | Care | Sten the shepherd, Ålberga |
| 12 | Who Takes the Honey? | Find | Alfhild the beekeeper, Dimmberga |
| 13 | The Foal Is Coming | Ferry | Ragnfrid of the horse farm, Torsgården |
| 14 | The Market Day | Race | Ulf the market warden, Kråkhamn |
| 15 | The Sick Calf | Heal | Gudrun the innkeeper, Vargvik |
| 16 | A Dress for Midsummer | Make | Sæunn the weaver, Guldvik |
| 17 | Midsummer Night | Deliver | Chieftain Eirik, Hjortingsala |
| 18 | The Kitten in the Boathouse | Find | Grandmother Åsa, Rimgården |
| 19 | The Stable | Build | Grandmother Åsa, Rimgården |
| 20 | Fog on the Lakes | Rescue | Gudrun the innkeeper, Vargvik |
| 21 | The Foal Comes Home | Ferry | Ragnfrid of the horse farm, Torsgården |
| 22 | Salt for Stormvik | Deliver | Tor the fisher, Stormvik |
| 23 | Charcoal for the Smith | Deliver | Hrafn the smith, Gäddarby |
| 24 | New Ribs for the Boat | Build | Bjarne the boatwright, Kråkhamn |
| 25 | Letters for the Chieftain | Deliver | Gudrun the innkeeper, Vargvik |
| 26 | Clay for the Potter | Fetch | Dagny the potter, Bergö |
| 27 | Bees for Solby | Deliver | Solveig of Solby, Solby |
| 28 | The Lost Lamb | Find | Sten the shepherd, Ålberga |
| 29 | Herbs for the Lakes | Deliver | Tova the healer, Laxön |
| 30 | The Mill Turns | Deliver | Astrid of the mill, Mjödkvarn |
| 31 | A Henhouse Full | Fetch | Grandmother Åsa, Rimgården |
| 32 | Honey Cakes | Deliver | Freya and Liv, Kråkhamn |
| 33 | The Chieftain's Feast | Deliver | Chieftain Eirik, Hjortingsala |
| 34 | The Ferryman's Tale | Explore | Orm the innkeeper, Hallvik |
| 35 | Wool for the Winter Cloth | Deliver | Sæunn the weaver, Guldvik |
| 36 | Flax in the Field | Make | Sæunn the weaver, Guldvik |
| 37 | Barley for the Brewer | Deliver | Knut the brewer, Lindtorp |
| 38 | A Proper Hold | Build | Bjarne the boatwright, Kråkhamn |
| 39 | The Messenger's Cold | Deliver | Inga the messenger, Vargvik |
| 40 | Hay for Frosttorp | Deliver | Arne of Frosttorp, Frosttorp |
| 41 | Sigvor's Cheese | Deliver | Sigvor the goat woman, Ålberga |
| 42 | A Cow of Our Own | Fetch | Grandmother Åsa, Rimgården |
| 43 | Pots for Ekvik | Deliver | Helga the fisher, Ekvik |
| 44 | Ragna's Broken Oar | Rescue | Tor the fisher, Stormvik |
| 45 | Torches for the Dark | Deliver | Orm the innkeeper, Hallvik |
| 46 | The Autumn Feast | Deliver | Orm the innkeeper, Hallvik |
| 47 | The Tipsy Uncle | Ferry | Orm the innkeeper, Hallvik |
| 48 | Geese for the Market | Deliver | Ulf the market warden, Kråkhamn |
| 49 | The Runestone | Build | Chieftain Eirik, Hjortingsala |
| 50 | The First Snow | Fetch | Grandmother Åsa, Rimgården |
| 51 | The Ice Breaks | Find | Grandmother Åsa, Rimgården |
| 52 | The Coughing Horse | Heal | Tova the healer, Laxön |
| 53 | The Lame Goat | Heal | Sigvor the goat woman, Ålberga |
| 54 | Barley in Spring | Make | Grandmother Åsa, Rimgården |
| 55 | The Great Hold | Build | Bjarne the boatwright, Kråkhamn |
| 56 | Bjørn's Salt Run | Deliver | Bjørn the salt trader, Kråkhamn |
| 57 | Eggs for the Spring Feast | Deliver | Gudrun the innkeeper, Vargvik |
| 58 | Colours for the Boat | Make | Bjarne the boatwright, Kråkhamn |
| 59 | The Canoe Race | Race | Freya and Liv, Kråkhamn |
| 60 | Hild's Wedding | Deliver | Hrafn the smith, Gäddarby |
| 61 | The Swarm | Rescue | Alfhild the beekeeper, Dimmberga |
| 62 | The Cracked Kiln | Build | Dagny the potter, Bergö |
| 63 | Hay for Ålberga | Deliver | Sten the shepherd, Ålberga |
| 64 | The Ferryman's Last Trip | Ferry | Orm the innkeeper, Hallvik |
| 65 | Shearing Time | Deliver | Sten the shepherd, Ålberga |
| 66 | The Chieftain's Horse | Ferry | Chieftain Eirik, Hjortingsala |
| 67 | A Brooch for Thora | Make | Thora, the chieftain's daughter, Hjortingsala |
| 68 | The Ducklings | Rescue | Freya and Liv, Kråkhamn |
| 69 | Fish for the Hunters | Deliver | Chieftain Eirik, Hjortingsala |
| 70 | The Boat Procession | Deliver | Chieftain Eirik, Hjortingsala |
| 71 | The Sunny Hill | Ferry | Arne of Frosttorp, Frosttorp |
| 72 | A Flock of Our Own | Fetch | Grandmother Åsa, Rimgården |
| 73 | The Bear Comes Back | Find | Alfhild the beekeeper, Dimmberga |
| 74 | A Striped Sail | Make | Sæunn the weaver, Guldvik |
| 75 | The Widest Hold | Build | Bjarne the boatwright, Kråkhamn |
| 76 | A Wedding at Frosttorp | Ferry | Solveig of Solby, Solby |
| 77 | Ale for Two Inns | Deliver | Knut the brewer, Lindtorp |
| 78 | The Sleepy Hens | Heal | Grandmother Åsa, Rimgården |
| 79 | The Smith's Bellows | Build | Hrafn the smith, Gäddarby |
| 80 | Grandmother's Birthday | Fetch | Tova the healer, Laxön |
| 81 | The Healers' Round | Heal | Tova the healer, Laxön |
| 82 | The Colt in the Mud | Rescue | Ragnfrid of the horse farm, Torsgården |
| 83 | Grain for the North | Deliver | Chieftain Eirik, Hjortingsala |
| 84 | The Wool Fair | Deliver | Ulf the market warden, Kråkhamn |
| 85 | The Goats on the Island | Rescue | Sigvor the goat woman, Ålberga |
| 86 | News for Everybody | Deliver | Inga the messenger, Vargvik |
| 87 | A Cow for Grim | Deliver | Old Grim of Svanetorp, Svanetorp |
| 88 | Flowers on the Hill | Make | Grandmother Åsa, Rimgården |
| 89 | The Pottery Market | Deliver | Dagny the potter, Bergö |
| 90 | Gudrun's Ring | Find | Gudrun the innkeeper, Vargvik |
| 91 | The Edge of the Forest | Deliver | Arne of Frosttorp, Frosttorp |
| 92 | The Longhouse Grows | Build | Grandmother Åsa, Rimgården |
| 93 | The Green Valley | Deliver | Chieftain Eirik, Hjortingsala |
| 94 | Bees for the Valley | Fetch | Grandmother Åsa, Rimgården |
| 95 | Apples for the Market | Deliver | Solveig of Solby, Solby |
| 96 | The Winter Stores | Fetch | Grandmother Åsa, Rimgården |
| 97 | Fish for Every Farm | Deliver | Tor the fisher, Stormvik |
| 98 | Invitations | Find | Grandmother Åsa, Rimgården |
| 99 | Food for the Feast | Fetch | Grandmother Åsa, Rimgården |
| 100 | The Feast at the Farm | Ferry | Grandmother Åsa, Rimgården |

### The arc

The missions tell the story of the players' farm, which grows from an old boat, three hens and a sheep to a farm with goats, a cow, a flock, bees, a filly, the sunny hill, the forest edge and the green valley, and of the people and the animals they help on the way. Tova's helpers become healers known on all the lakes. The last missions bring in the stores for the winter and end with a feast at the farm, to which all the friends from all the lakes come.

### Stars

Each mission gives 1 to 3 stars, by how many days it took against its "days" (3 stars without them): within the days, three; two days later, two; later still, one. Nothing ever fails. Stars are shown on the board of the tasks; no other scores.

## 11. The trips and the saves

* The game saves in every port and at the homestead, as plain data (as in Bird Dog).
* A **session** is a trip: from a port to a port, with a mission or free trading. At the end of a trip the game shows what happened (silver, goods, stars, the news), and the players can stop with one click (pillar 4).
* Several voyages (save files) for several families or children.

## 12. Screens

* The **start**: the language, the voyage (the save), one or two players.
* The **farm**: Grandmother Åsa, the animals, the store, the fields and the plots to buy, the buildings, the boathouse (choose the ship, change the looks), the mission board.
* The **lakes** (the level): rowing, the minimap, the news, the cargo, the day.
* The **port**: the market, the people (missions, talk), the boatwright, the booster stall.
* The **map** of the region: the settlements, what they make and want (as far as the players know), the news, the missions.

# Technical design

* **Godot 4.6 (.NET)**, GDScript for the game and C# for the vision (`scenes/vision/`), as now.
* **The world** comes from `dev/maps/make_lakes.py`, extended to regions: several lakes, sounds, rivers with a current, portages, settlements on the shores, the routes of the NPC boats. The data lives in `data/world/<region>.json`.
* **The economy** is plain data: the goods, the settlements (what they make and want), the events (`data/economy/`), and a small simulation (prices, recovery, events) which runs in days, unit-tested.
* **The NPC boats** follow their routes with the same boat physics as the players (`RowBoat`), and a small set of behaviours (sail, wait at a jetty, hail, offer a trade, need help).
* **The farm** is plain data too (the animals, the plots, the buildings, the store), with a simulation by days (feed, goods, cheese, young, growth), unit-tested: no animal ever dies, whatever the numbers, and the young come steadily, never faster for a bigger herd.
* **The news** are made from templates and the state of the economy ("{good} sells for {price} in {place}"), so they are always true when told.
* **The missions** are data (`data/missions/<nnn>_<id>/mission.json`), built from the steps of section 10, as in Bird Dog; `Missions` checks them when it loads them, and `tests/godot/test_missions.gd` plays all of them through.
* **Translations (built):** English and 16 more languages, listed in `translations/languages.json` (Arabic, Danish, German, Spanish, French, Hindi, Italian, Japanese, Korean, Norwegian, Russian, Bosnian/Croatian/Serbian as one text, Albanian, Swedish, Turkish and Chinese), chosen on the very first screen (`LanguageSelect`, later the card "Language" of the journeys) and remembered (`Languages`, `user://settings.cfg`).
  * Every text is a whole English sentence, the message ID, with named placeholders (`Grammar.text("Row to {place}.", {"place": ...})`); nothing is glued together from pieces. A translation picks the grammatical forms it needs: the case of an inserted name (`{place@to}`, `{good@gen}`, `{thing@acc}`, each a message with that context), a word agreeing with a number by the plural rule of the language (`{count|crate|crates}`, up to six forms in Arabic), and the words for the addressed rowers by their number and gender (`{crew|one boy|one girl|two rowers|two girls}`, from the looks of the journey). The data holds nouns as they stand in a sentence ("salt", "the sunny hill") and counted phrases (`"counted": "{count|a barrel of ale|{count} barrels of ale}"`).
  * The cards carry an English `id` beside their translated title, so the icons, the autopilot and the end-to-end bot work in every language.
  * Lines break at the spaces, and in Chinese and Japanese between the characters (`Wrapping`); Arabic aligns the board right. The screens keep their layout from left to right in every language (`internationalization/rendering/root_node_layout_direction` of `project.godot`), since the game lays them out itself; Godot would mirror the controls for Arabic.
  * The font of the game falls back on the Noto fonts of `assets/fonts/` (Arabic, Devanagari, and Chinese, Japanese and Korean cut to the characters of the translations); only the chosen language brings its font, since the other scripts would change the lines of every text.
  * The translations are drafts, marked fuzzy, until a native speaker reviews them in the game (CONTRIBUTING.md, "Translations").

# Open questions

1. ~~**The title**~~: decided, "Drunken Vikings", with ale and mead in the game (section 2).
2. ~~**The scope**~~: decided, region 1 first (about 20 missions), play-test, then grow.
3. **The world**: one big continuous map (truly open), or regions joined by the rivers and the portages (simpler, and a natural place for the trips to end)?
4. **The farm and the trading**: how much of the game is the farm (a calm side, as described) and how much the trading? Should the farm make missions of its own (the harvest, a lost sheep)?
5. ~~**Two players**~~: decided, one boat, each player pulls the oar on their side, and the boat turns away from the stronger rower (section 9).
6. **How much to read**: the children of eight read little; the news and the market rely on pictures, but do we want voices (recorded or synthesized offline)?
7. **The length of a level**: the first level takes about eight minutes of rowing (180 strokes); is that right for the age, or should the legs be shorter?
