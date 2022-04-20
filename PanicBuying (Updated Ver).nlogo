globals [
  outside-patches
  supermarket-patches
  num-shortage-news ;; number of agents who posted on social media on shortage of goods
  num-unsatisfied ;; number of agents who didn't manage to buy due to out of stock
]

breed [
  humans human
]

humans-own [

  perceived-scarcity
  radius-factor
  fear-factor
  social-factor
  panic-buy-prob
  shelf-assigned
  panic-buying?
  food-level
  buying-lag-count
  initial-status

]

patches-own [
  shelf-id
  shelf-stock
]

to setup
  clear-all
  reset-ticks
  setup-humans
  setup-supermarket
  set outside-patches patches with [pcolor = green]
  set supermarket-patches patches with [pcolor = blue]

  ask humans [
    move-to one-of outside-patches
    set food-level 10
    set panic-buying? false
  ]

end

to go
  tick

  ;; 1. compute panic buying probability of every agent (done)
  compute-panic-buy-prob

  ;; 2. trigger panic buying behavior across all agents (done)
  trigger-panic-buy

  ;; 3. set colors of agents that are panic buying to be red, to differentiate.
  ask humans [ ifelse panic-buying? [set color red ] [set color white ] ]

  ;; 4. move outside agents (on green patch) across the grid
  move-outside-agents

  ;; 5. move supermarket agents (on blue patch) around the supermarket
  supermarket-agents-move
  supermarket-agents-buy


  ;; no need for update of fear factor, since that's innate assuming an ongoing pandemic.
  ;; perceived scarcity is not innate, agent's perceived scarcity will be influenced if agent notices that there's sufficient goods available.

  update-social-factor

  set num-shortage-news 0 ;; reset for next tick

  ;; assume 1 day = 10 ticks.

  let num-days ticks / 10
  if num-days mod restock-frequency = 0 [ ask patches with [pcolor = cyan] [ set shelf-stock shelf-stock + restock-qty ] ]

end

;; ---------------------------- SETUP HUMANS PROCEDURE ---------------------------- ;;
to setup-humans
  ;; 100 humans, positioned randomly
  create-humans human-population [
    set shape "person" set color white
    set-perceived-scarcity
    set radius-factor 0 ;; initialize as 0 since agents starts off on outside patches, not supermarket patches.
    set-fear-factor
    set social-factor 0 ;; initialize as 0 since spread of food shortage news online hasn't started
  ]
end

;; ---------------------------- SETUP SUPERMARKET PROCEDURE ---------------------------- ;;
to setup-supermarket
  ;; size of supermarket – 17 x 17
  ask patches [
    ifelse pxcor >= -8  and pxcor <= 8 and pycor >= -8 and pycor <= 8
    [ set pcolor blue ]

    [ set pcolor green ]
  ]

  ;; setup 4 item shelves & assign shelves with ID
  let i [ 4 -4 ]
  let num 1
  let shelf-list ( list patches with [(member? pxcor i) and (member? pycor i)] )

  foreach shelf-list [
    shelf -> ask shelf [

      ;; set shelf id, pcolor, plabel & shelf-stock of shelf.
      set shelf-id num
      set pcolor cyan
      set plabel shelf-id set plabel-color black
      set shelf-stock initial-stock-qty

      ;; set shelf id, pcolor & shelf-stock of neighbouring patches.
      ask neighbors [ set pcolor cyan set shelf-id num set shelf-stock initial-stock-qty ]

      ;; counter
      set num num + 1
    ]
  ]
end

;; ---------------------------- OUTSIDE AGENT MOVEMENT PROCEDURE ---------------------------- ;;
to move-outside-agents

  ask humans with [pcolor = green] [

    ;; if agent is in panic buying mode and not in supermarket, food level doesn't decrease. straightaway head towards supermarket, 3 steps every tick.
    ifelse panic-buying? = true [
      ifelse xcor < 0 [
        set xcor xcor + 3
        ifelse ycor < 0 [ set ycor ycor + 3 ] [ set ycor ycor - 3 ]
      ]
      [ set xcor xcor - 3
        ifelse ycor < 0 [ set ycor ycor + 3 ] [ set ycor ycor - 3 ]
      ]
    ]

    ;; if agent is NOT in panic buying mode, agent moving around as per normal.
    [
      ;; if agent's food level is less than 5 and not in supermarket, agent starts to be hungry.
      ;; agent makes its way towards the supermarket to buy 1 unit of food.

      ifelse food-level < 5 [
        ifelse xcor < 0 [
          set xcor xcor + 3
          ifelse ycor < 0 [ set ycor ycor + 3 ] [ set ycor ycor - 3 ]
        ]
        [ set xcor xcor - 3
          ifelse ycor < 0 [ set ycor ycor + 3 ] [ set ycor ycor - 3 ]
        ]
      ]

      ;; if agent's food level is more than or equal to 5, agent moves as per normal randomly on the outside patches and consume 1 unit of food for every movement.
      [
        set food-level food-level - 1
        move-to one-of outside-patches
      ]
    ]
  ]

end

;; ---------------------------- SUPERMARKET AGENT MOVEMENT PROCEDURE ---------------------------- ;;

;; 1. Simulate movement of agents within supermarket
to supermarket-agents-move

  ask humans with [pcolor = blue or pcolor = cyan] [

    ;; 1. assign agents to an item shelf first

    ;; if agent landed on a non-shelf patch in supermarket, move agent to shelf patch.
    ifelse [ shelf-id ] of patch xcor ycor = 0 [
      set shelf-assigned 1 + random 4
      let shelf-num shelf-assigned
      move-to one-of patches with [ shelf-id = shelf-num ]
    ]

    ;; if agent landed on a shelf patch in supermarket
    [
      set shelf-assigned [ shelf-id ] of patch xcor ycor
    ]
  ]
end

;; 2. Simulate agent buying behavior with buying lag within supermarket
to supermarket-agents-buy

  ask humans with [pcolor = cyan] [
    set buying-lag-count buying-lag-count + 1
    ifelse buying-lag-count = 1 [
      set initial-status panic-buying?
      ;; first round of buying – agent buys item (1 unit if normal, 10 units if panic buy)
      ifelse panic-buying? = true [ panic-buy ] [ normal-buy ]
    ]

    ;; for checking 2nd & 3rd round of buying lag
    [
      ;; for agents that entered supermarket as normal buying, if they got influenced to panic buy, buying lag will restart, agent will undergo panic buying path
      ifelse initial-status = false [
        ifelse (panic-buying? != initial-status) [ set buying-lag-count 0 ] [ checkout ]
      ] [ checkout ]
    ]
  ]


end

;; ---------------------------- SUPERMARKET AGENT PANIC BUY PROCEDURE ---------------------------- ;;
to panic-buy

  ;; check if there's shortage of goods – if there is, update perceived scarcity to max. if there isnt, check if can buy 10 units of good.

  let qty-to-buy 0

  ;; count total number of agents on the patch
  let num-humans 0
  let shelf-num shelf-assigned
  ask patches with [ shelf-id = shelf-num ] [ set num-humans num-humans + count humans-here ]

  ;; if shelf able to cater to demands of all agents on that shelf, there's no shortage of goods.
  ifelse [ shelf-stock ] of patch xcor ycor >= 10 * num-humans [
    panic-buy-sufficient shelf-num
  ]

  ;; if there's shortage of goods, move agents to another patch.
  ;; agent will increase perceived scarcity to max and also spread food shortage news online to influence other agents (social factor)
  [  panic-buy-insufficient num-humans ]


end

;; ---------------------------- SUPERMARKET AGENT PANIC BUYING (SUFFICIENT) PROCEDURE ---------------------------- ;;
to panic-buy-sufficient [ shelf-num ]

  ;; 1. agent realize that there's sufficient goods, perceived scarcity updated to 0 (min).
  set perceived-scarcity 0

  ;; 2. is agent able to buy 10 units of good? (check for rationing)
  ifelse (intervention-type = "rationing" or intervention-type = "rationing & assurance") [
   rationing-buy shelf-num
  ]

  ;; if no ration limit, panic buying agent able to buy 10 unit of goods.
  [ let qty-to-buy 10 ask patches with [ shelf-id = shelf-num ] [ set shelf-stock shelf-stock - qty-to-buy ] set food-level food-level + qty-to-buy ]

end

;; ---------------------------- PANIC BUYING WITH RATIONING PROCEDURE ---------------------------- ;;
to rationing-buy [ shelf-num ]

    ;; panic buying intent off, since implementation of ration meant that agents cannot panic buy when they're in supermarkets.
    set panic-buying? false
    set color white

    ;; for rationing, agent only able to buy ration limit.
    if ration-limit < 10 [
      let qty-to-buy ration-limit
      ask patches with [ shelf-id = shelf-num ] [ set shelf-stock shelf-stock - qty-to-buy ]
      set food-level food-level + qty-to-buy
    ]

end

;; ---------------------------- SUPERMARKET AGENT PANIC BUYING (SHORTAGE) PROCEDURE ---------------------------- ;;
to panic-buy-insufficient [ num-humans ]

  ;; 1. agent realize that there's a scarcity goods, perceived scarcity updated to 1 (max).
  set perceived-scarcity 1

  ;; 2. agent realize that there's a scarcity goods, post on social media, influence other agents to panic buy.
  set num-shortage-news num-shortage-news + 1

  ;; 3. move agent to another patch with sufficient stock
  let num-sufficient count patches with [shelf-stock >= 10 * num-humans]
  ifelse num-sufficient > 0 [
    move-to one-of patches with [shelf-stock >= 10 * num-humans]

    let shelf-num 0
    ;; 4. is agent able to buy 10 units of good? (check for rationing)
    ifelse (intervention-type = "rationing" or intervention-type = "rationing & assurance") [
      set shelf-num [ shelf-id ] of patch xcor ycor
      rationing-buy shelf-num
    ]

    ;; 5. if no ration limit, panic buying agent able to buy 10 units of good.
    [ let qty-to-buy 10 ask patches with [ shelf-id = shelf-num ] [ set shelf-stock shelf-stock - qty-to-buy ] set food-level food-level + qty-to-buy ]

  ] [ set num-unsatisfied num-unsatisfied + 1 ] ;; keep track of count of unsatisfied customers

end

;; ---------------------------- SUPERMARKET AGENT NORMAL BUYING PROCEDURE ---------------------------- ;;
to normal-buy

  let qty-to-buy 1

  ;; count total number of agents on the patch
  let num-humans 0
  let shelf-num shelf-assigned
  ask patches with [ shelf-id = shelf-num ] [ set num-humans num-humans + count humans-here ]

  ;; if shelf able to cater to the maximum demands of all agents on that shelf, there's no shortage of goods.
  ifelse [ shelf-stock ] of patch xcor ycor >= 10 * num-humans [ normal-buy-sufficient shelf-num ]

  ;; if there's shortage of goods, move agents to another patch.
  [  normal-buy-insufficient num-humans ]


  ;; update radius factor
  update-radius-factor



end

;; ---------------------------- SUPERMARKET AGENT NORMAL BUYING (SUFFICIENT) PROCEDURE ---------------------------- ;;
to normal-buy-sufficient [ shelf-num ]

  ;; 1. agent realize that there's sufficient goods, perceived scarcity updated to 0 (min).
  set perceived-scarcity 0

  ;; 2. agent proceeds to buy 1 unit of good.
  let qty-to-buy 1
  ask patches with [ shelf-id = shelf-num ] [ set shelf-stock shelf-stock - qty-to-buy ]
  set food-level food-level + qty-to-buy

end

;; ---------------------------- SUPERMARKET AGENT NORMAL BUYING (SHORTAGE) PROCEDURE ---------------------------- ;;
to normal-buy-insufficient [ num-humans ]

  ;; 1. move agent to another patch with sufficient stock
  let num-sufficient count patches with [shelf-stock >= 10 * num-humans]
  ifelse num-sufficient > 0 [
    move-to one-of patches with [shelf-stock >= 10 * num-humans]

    ;; 2. agent proceeds to buy 1 unit of good.
    let shelf-num [ shelf-id ] of patch xcor ycor
    let qty-to-buy 1
    ask patches with [ shelf-id = shelf-num ] [ set shelf-stock shelf-stock - qty-to-buy ]
    set food-level food-level + qty-to-buy
  ] [ set num-unsatisfied num-unsatisfied + 1 ]

end


;; ---------------------------- SUPERMARKET AGENT CHECKOUT PROCEDURE ---------------------------- ;;
to checkout

  ifelse panic-buying? = true [
    ;; during second round of buying, agent doesn't buy as it has already picked up items.
    ;; this is to factor in buffer time for checkout and for agent to roam around supermarket
    ;; for agents that are normal buying – this buffer time allows them to see if other agents are panic buying and influence them to panic buy as well.
    if buying-lag-count = 2 [
      if (intervention-type = "rationing" or intervention-type = "rationing & assurance") [ set panic-buying? false set color white ]
      move-to one-of supermarket-patches
    ]

    ;; during third round of buying, agent checks out and leave supermarket. buying lag count resets
    ;; for agents in panic buy mode, they will go back to non panic buying mode.
    if buying-lag-count = 3 [
      move-to one-of outside-patches
      set buying-lag-count 0
      set panic-buying? false
    ]
  ]

  ;; if panic-buying is false
  [
    ;; move agent around after buying 1 unit of good
    if buying-lag-count = 2 [ move-to one-of supermarket-patches ]

    ;; agent checks out and leave supermarket.
    if buying-lag-count = 3 [
      move-to one-of outside-patches
      set buying-lag-count 0
      set panic-buying? false
    ]
  ]


end

;; ---------------------------- SETUP PERCEIVED SCARCITY PROCEDURE ---------------------------- ;;
;; set the perceived-scarcity based on the paper by Hu
;; perceived-scarcity: how likely an individual will be influenced to panic buy given their perceived scarcity
;; strongly disagree: 25.6% // disagree: 18.7% // neutral: 25.1% // agree: 18.1% // strongly agree: 12.5%
to set-perceived-scarcity
  ask humans [
    let j random 11 / 10
    ( ifelse
      j <= 0.256 [ set perceived-scarcity 0 / 4 ] ;; strongly disagree
      j <= 0.443 [ set perceived-scarcity 1 / 4 ] ;; disagree
      j <= 0.694 [ set perceived-scarcity 2 / 4 ] ;; neutral
      j <= 0.875 [ set perceived-scarcity 3 / 4 ] ;; agree
      j <= 1 [ set perceived-scarcity 4 / 4 ] ;; strongly agree
    )
  ]
end

;; ---------------------------- SETUP FEAR FACTOR PROCEDURE ---------------------------- ;;
;; fear: how likely an individual will panic buy due to fear of uncertainty
;; totally disagree: 25.3% // disagree: 42.7% // neutral: 6.65% // agree: 15.7% // totally agree: 9.65%
to set-fear-factor
  ask humans [
    let j random 11 / 10
    ( ifelse
      j <= 0.253 [ set fear-factor 0 / 4 ] ;; totally disagree
      j <= 0.68 [ set fear-factor 1 / 4 ] ;; disagree
      j <= 0.7465 [ set fear-factor 2 / 4 ] ;; neutral
      j <= 0.9035 [ set fear-factor 3 / 4 ] ;; agree
      j <= 1 [ set fear-factor 4 / 4 ] ;; totally agree
    )
  ]
end

;; ---------------------------- UPDATE RADIUS FACTOR PROCEDURE ---------------------------- ;;
;; agents that are not panic buying and are in supermarket
to update-radius-factor
  let total-people count humans in-radius 4
  let panic-people 0
  ask humans in-radius 4 [
    if color = red [ set panic-people panic-people + 1 ]
  ]
  ifelse total-people = 0 [ set radius-factor 0 ] [ set radius-factor (panic-people / total-people) ]
end


;; ---------------------------- UPDATE SOCIAL FACTOR PROCEDURE ---------------------------- ;;
to update-social-factor
  ask humans [ set social-factor num-shortage-news / human-population ]
end


;; ---------------------------- COMPUTE PANIC BUYING PROBABILITY PROCEDURE ---------------------------- ;;

;; panic buying probability is based on perceived scarcity, radius, social and fear factors.
to compute-panic-buy-prob
  ask humans [

    ;; alter factor values based on intervention type before computing panic buy probability.
    ( ifelse
      intervention-type = "rationing" [ set radius-factor 0 ]
      intervention-type = "assurance" [ set perceived-scarcity 0 ]
      intervention-type = "rationing & assurance" [ set perceived-scarcity 0 set radius-factor 0 ]
    )

    ;; material-demand comprises of only perceived scarcity.
    let material-demand perceived-scarcity

    ;; emotional-panic comprises of radius, fear and social factors with assumed equal weightage.
    let emotional-panic 1 / 3 * radius-factor + 1 / 3 * fear-factor + 1 / 3 * social-factor

    ;; compute agent's panic buying probability based on 2 overarching factors with assumed equal weightage.
    set panic-buy-prob 1 / 2 * material-demand + 1 / 2 * emotional-panic

  ]
end

;; ---------------------------- TRIGGER PANIC BUYING PROCEDURE ---------------------------- ;;
to trigger-panic-buy

  ;; only trigger panic buying if humans are not in panic buying mode
  ask humans with [panic-buying? = false] [
    let k random 1001 / 1000
    ifelse k <= panic-buy-prob [ set panic-buying? true  ] [ set panic-buying? false ]
  ]

end


to-report num-panic-buying
  report count humans with [panic-buying? = true]
end

to-report prop-panic-buying
  report ( count humans with [panic-buying? = true] / human-population ) * 100
end

to-report num-unsatisfed-cust
  report num-unsatisfied
end

to-report inventory-1
  report [shelf-stock] of one-of patches with [ shelf-id = 1 ]
end

to-report inventory-2
  report [shelf-stock] of one-of patches with [ shelf-id = 2 ]
end

to-report inventory-3
  report [shelf-stock] of one-of patches with [ shelf-id = 3 ]
end

to-report inventory-4
  report [shelf-stock] of one-of patches with [ shelf-id = 4 ]
end

to-report num-days-passed
  report floor ( ticks / 10 )
end
@#$#@#$#@
GRAPHICS-WINDOW
768
10
1330
573
-1
-1
10.863
1
10
1
1
1
0
1
1
1
-25
25
-25
25
0
0
1
ticks
30.0

BUTTON
30
23
96
56
NIL
setup\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
106
23
169
56
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
180
24
285
57
go (forever)
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
26
91
271
124
human-population
human-population
50
200
200.0
5
1
NIL
HORIZONTAL

MONITOR
355
72
681
117
Number of Agents that are in Panic Buying Mode
num-panic-buying
0
1
11

PLOT
354
177
695
328
Number of panic buying agents
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count turtles with [color = red]"

CHOOSER
26
137
211
182
intervention-type
intervention-type
"none" "rationing" "assurance" "rationing & assurance"
3

TEXTBOX
358
21
692
63
To monitor proportion of population with intent to panic buy
14
0.0
1

TEXTBOX
29
193
300
244
Set ration limit \n(For rationing intervention only)
14
125.0
1

SLIDER
28
234
200
267
ration-limit
ration-limit
1
10
3.0
1
1
items
HORIZONTAL

SLIDER
27
365
228
398
restock-frequency
restock-frequency
1
14
7.0
1
1
days
HORIZONTAL

TEXTBOX
31
277
181
311
Set restock frequency and quantity\n
14
125.0
1

SLIDER
27
406
199
439
restock-qty
restock-qty
500
1000
500.0
10
1
units
HORIZONTAL

SLIDER
28
322
284
355
initial-stock-qty
initial-stock-qty
500
1000
500.0
50
1
items per shelf
HORIZONTAL

MONITOR
352
344
623
389
Number of News Online on Food Shortage
num-shortage-news
17
1
11

MONITOR
355
125
690
170
Percentage (%) of Population with Panic Buying Intent
prop-panic-buying
3
1
11

MONITOR
356
405
574
450
number of unsatisfied customers
num-unsatisfed-cust
17
1
11

MONITOR
31
535
205
580
Inventory Levels of Shelf 1
inventory-1
17
1
11

MONITOR
214
590
388
635
Inventory Levels of Shelf 4
inventory-4
17
1
11

MONITOR
30
591
204
636
Inventory Levels of Shelf 3
inventory-3
17
1
11

MONITOR
214
534
388
579
Inventory Levels of Shelf 2
inventory-2
17
1
11

TEXTBOX
30
499
350
533
Track Inventory Levels across Shelves
16
105.0
1

MONITOR
430
531
593
576
Elapsed Number of Days
num-days-passed
0
1
11

TEXTBOX
427
497
719
521
Number of Days (10 ticks = 1 Day)
16
105.0
1

@#$#@#$#@
## WHAT IS IT?

The overarching goal of this NetLogo simulation is to observe the impacts of policy interventions on panic buying intent across the population. As such, our hypothesis is that the proportion of the entire population with the intent to panic buy will be reduced by 50% with the implementation of interventions by supermarket policymakers. We will address if our simulation has proved this hypothesis right in Section 7. Moreover, we can simulate different restock frequencies and quantities to determine how frequent supermarkets should be restocking the shelves to prevent the worsening of panic buying across the population. This allows supermarkets to better plan their resources and handle panic buying crises.  

## HOW IT WORKS

Agent Variables 
1. Perceived Scarcity (perceived-scarcity) [ Material Demand ]
2. Influence from Nearby Panic Buying Agents (radius-factor) [ Emotional Panic ]
3. Social Influence from Food Shortage News Online (social-factor) [ Emotional Panic ]
4. Fear of Uncertainty (fear-factor) [ Emotional Panic ]

Panic Buying Intent Probability 
P(PBI) = 0.5 * (1/3 * Si + 1/3 Fi + 1/3 Ri ) + 0.5 * (PSi)
where Si : Social Factor, Fi : Fear Factor, Ri : Radius Factor, PSi : Perceived Scarcity


## THINGS TO TRY

1. Adjust intitial stock quantity, restock quantity and restock frequency to observe its impact on panic buying development across the population. 

2. Adjust the rationing limit to determine the impact on stock levels and panic buying development across the population. 

3. Select intervention type to determine the impacts on panic buying development for every combination of policy intervention. 

## THINGS TO NOTICE

A BehaviorSpace experiment was conducted to determine the varying impacts that the type of intervention has on panic buying. We observe that among the 4 intervention types, utilizing both rationing and assurance yielded the greatest effect as it managed to keep the number of panic buying agents relatively low compared to the other methods. The approach of rationing and assurance compared to having no interventions at all resulted in an approximate 85% decrease in the number of panic buying agents. This is much greater than the 50% decrease that our hypothesis predicted. Furthermore the restocking frequency is also varied. It is evident that the restocking frequency does indeed play an important role in the mitigation of panic buying, for instance in the “rationing” approach, there is a significant divergence in the number of panic buyers between the 3 and 7 day restocking frequency.

Another BehaviorSpace experiment was conducted to monitor the stock levels across supermarkets, assuming that there are no restocks and rationing is limited to 3 goods to mimic the rationing policies across supermarkets in Singapore. 10 BehaviorSpace experiments were conducted and the average total stocks across all 4 shelves are monitored across all 10 experiments and visualized on the graph shown above. As we can see on the left, scarcity of goods in supermarkets happens much faster (within 20 ticks) when there are no interventions. However, when rationing and assurance are implemented, scarcity of goods happens at a much later time period (within 40 ticks). This suggests that the implementation of rationing and assurance is effective to slow down the depletion of goods at supermarkets to potentially prevent panic buying intent across the population to worsen. From this BehaviorSpace experiment, we are able to infer that should policymakers not decide to intervene, supermarkets should restock every 20 ticks (2 days)  to contain the spread of panic buying intent and prevent customers from spreading the news of shortage of goods at supermarkets. If policymakers were to intervene and implement assurance and rationing, they are recommended to restock supermarket goods every 40 ticks (4 days).


## EXTENDING THE MODEL

For simplicity, we assumed that all 4 item shelves are homogenous and agents are randomly allocated to an item shelf upon entering the supermarket to purchase the goods they desire. However, a possible extension of this model would be to implement item shelves for different foodstuff, to differentiate and analyze which goods are higher in demand during panic buying crises.



@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
