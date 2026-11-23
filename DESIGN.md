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

## 7a. The farm

The players' farm lies on the shore of the home lakes, with its own jetty. Grandmother Åsa keeps it while they are away, and every time they row home, they see it and run it with the hand cursor (a short, calm screen between the trips).

### The animals

| Animal | Costs | Eats (per day) | Gives | Sells for |
|---|---|---|---|---|
| Hens | little | A little grain | Eggs | little |
| Sheep | some | Hay | Wool (and lambs in spring) | some |
| Goats | some | Hay or leaves | Milk, cheese | some |
| Pigs | some | Grain and scraps | Piglets | some |
| Cows | much | Much hay | Milk, butter, calves | much |
| Bees (hives) | some | Nothing (flowers) | Honey, wax | some |
| A horse | very much | Hay and oats | Pulls the plough (bigger fields) | much |

* The players **buy** the animals at the markets and the farms of the lakes, and bring them home by boat (a goat in the boat takes the place of a crate, and bleats).
* The animals **need feed**: hay and grain, from the farm's own fields or bought and brought by boat. The farm's store shows how many days the feed lasts.
* **Without feed, no animal dies or suffers harm.** It only stops giving (no eggs, no milk) and looks sad, until the players bring feed; Grandmother Åsa reminds them gently. (The game is for children: no animal ever comes to harm.)
* The animals **give goods** every day of the trips (eggs, wool, milk, honey), which wait in the farm's store; the players take them on the next trip and sell them, or use them for missions.
* The young (lambs, piglets, calves) grow up over some days and can be **sold** at the markets as living animals (they go to other farms, never to the butcher in the game).

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

| Ship | Rowers | Sail | Hold | Unlocks |
|---|---|---|---|---|
| **Rowing boat** (the start) | The players | No | 4 crates | The home lakes |
| **Færing** (a light four-oared boat) | The players and 2 crew | No | 8 crates | The rivers (fast enough against the current) |
| **Karve** (a small ship) | The players and 6 crew | A small square sail | 16 crates | The long lakes, the northern waters |
| **Knarr** (the trading ship) | The players and 4 crew | A big square sail | 40 crates | The sea |
| **Longship** (the prize at the end) | The players and 20 crew | A great sail | 20 crates | Everything, the fastest |

* **The crew rows with the players.** Each stroke of the players is the beat for the whole crew: a bigger ship is heavier, but has more rowers, so a stroke still matters as much. The crew is paid a little silver per trip (it is part of the trading sums, not a punishment).
* **The sail** carries the ship with the wind, but rowing still makes it faster, and against the wind only rowing helps. So the exercise never stops mattering.
* A ship is bought once and kept; the players choose which one to take for a trip (the small boat fits the narrow rivers, the knarr does not).

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

### Region 1: The Home Lakes (missions 1 to 20)

The first region teaches the rowing, the trading, the farm and the animals, and makes the players Tova's helpers. The story: Ylva and Sigrid get Grandmother Åsa's old rowing boat and a small farm with three hens and a sheep, and want to make the farm a home for many animals.

| # | Title | Kind | Summary |
|---|---|---|---|
| 1 | Follow the Longship | Follow | The longship of the traders passes by; follow it to the market village, and learn to row and to steer. (The level which works now.) |
| 2 | A Pet of My Own | Ferry | At the market, a girl has more kittens (or puppies, or little goats) than she can keep; choose one, name it, and row it home. |
| 3 | Eggs for the Inn | Deliver | Sell the eggs of the hens to the inn by the sound; the first silver, and the first look at a market. |
| 4 | The Sneezing Sheep | Heal | The sheep sneezes. Tova says: thyme from the island of the herbs. Fetch it, and the sheep is well; Tova asks for help with more animals. |
| 5 | News on the Water | Find | Hail three boats on the lakes and ask about the best price for wool; sell the wool where it pays most. |
| 6 | Two Goats for the Farm | Fetch | Buy two goats at the farm across the lake and row them home (they bleat all the way). Build them a pen. |
| 7 | The Swan in the Net | Rescue | A swan is tangled in a fisher's old net in the reeds; row carefully between the reeds, free it, and the fisher gives you a fish trap. |
| 8 | Ale for the Wedding | Deliver | Astrid of the mill marries Bjarne the boatwright. Bring the ale from the brewer in time, without spilling (row smoothly). |
| 9 | Flowers for the Bride | Fetch | Gather the flowers for the bride's crown from three meadows by the lakes, and the blue dye for her ribbons. Dance at the wedding. |
| 10 | The Lamb in the Cold Night | Care | A late frost; the farm on the north shore has newborn lambs. Bring blankets and warm milk before the night falls. |
| 11 | Who Takes the Honey? | Find | The honey of the beekeeper disappears. Ask the boats, follow the paw prints on the shore: a bear cub! Bring him back to his mother on the far shore with a pot of honey. |
| 12 | The Foal Is Coming | Care | The mare of the horse farm is about to foal; row Tova there quickly, and the foal is born. The family promises you a foal when it is grown. |
| 13 | The Market Day | Race | The great market day on the island; be the first with the new honey and the cheese of the goats, ahead of the friendly rival Gunnhild, who becomes a friend. |
| 14 | The Sick Calf | Heal | The calf of the inn's cow does not drink. Tova needs chamomile and a warm stone; bring both, and sit with the calf till it drinks. |
| 15 | A Dress for Midsummer | Make | Bring wool, the red dye of the madder and a silver clasp to the weaver; she makes the players dresses for midsummer. |
| 16 | Midsummer Night | Deliver | Bring the mead and the flowers for the midsummer feast on the island, row in the boat procession by torchlight, and see the dance. |
| 17 | The Kitten in the Boathouse | Find | The pet is gone! Ask everybody on the lakes; it hid in the boathouse of the boatwright and has kittens of its own. |
| 18 | The Stable | Build | Bring timber, nails from the smith and tar for a stable at the farm, ready for the foal. |
| 19 | Fog on the Lakes | Rescue | A fog falls; the children of the inn rowed out to the islands. Find them in the fog (listen to their calls) and guide them home. |
| 20 | The Foal Comes Home | Ferry | The foal is grown enough: bring it home on a raft from the horse farm, row gently, and the farm has its first horse. The way to the Long Lake opens. |

### The arc

The missions tell, region by region, the story of the players' farm and trading house, which grow from a rowing boat, three hens and a sheep to a knarr which sails the sea and a farm full of animals, and of the people and the animals they help on the way. Tova's helpers become healers known on all the lakes. The last missions bring in the stores for the winter and end with a feast at the farm, to which all the friends from all the lakes come, with their animals.

### Stars

Each mission gives 1 to 3 stars, for the time and for doing it well (a delivery on time, the ale not spilled, the animal well again). Stars unlock some looks and parts of the farm, and are shown on the mission list; no other scores.

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
* **The farm** is plain data too (the animals, the plots, the buildings, the store), with a simulation by days (feed, goods, growth), unit-tested: no animal ever dies, whatever the numbers.
* **The news** are made from templates and the state of the economy ("{good} sells for {price} in {place}"), so they are always true when told.
* **The missions** are data (`data/missions/<nn>_<id>/`), built from the blocks of section 10, as in Bird Dog.
* **Translations** from the start (English, German, Swedish, ...), as in our other games.

# Open questions

1. ~~**The title**~~: decided, "Drunken Vikings", with ale and mead in the game (section 2).
2. ~~**The scope**~~: decided, region 1 first (about 20 missions), play-test, then grow.
3. **The world**: one big continuous map (truly open), or regions joined by the rivers and the portages (simpler, and a natural place for the trips to end)?
4. **The farm and the trading**: how much of the game is the farm (a calm side, as described) and how much the trading? Should the farm make missions of its own (the harvest, a lost sheep)?
5. ~~**Two players**~~: decided, one boat, each player pulls the oar on their side, and the boat turns away from the stronger rower (section 9).
6. **How much to read**: the children of eight read little; the news and the market rely on pictures, but do we want voices (recorded or synthesized offline)?
7. **The length of a level**: the first level takes about eight minutes of rowing (180 strokes); is that right for the age, or should the legs be shorter?
