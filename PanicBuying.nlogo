globals [ outside-patches supermarket-patches total-food-bought ]

breed [ humans human ]

humans-own [
  influenced-factor ;; done
  perceived-scarcity ;; done
  food-level
  panic-buy-prob
  panic-buying?
  ;; satisfaction   ;; implement later only if there's time
  num-relatives ;; number of links to other agents that are panic buying
  num-radius ;; number of agents in vision radius that are panic buying (Do we need this? This variable isn't used anywhere)
  relatives-factor
  radius-factor
  buying-lag-count
]

to setup
  clear-all
  reset-ticks

  ;; 100 humans, positioned randomly
  create-humans human-popln [ set shape "person" set color white ]

  ;; size of supermarket – 31 x 31
  ask patches [
    ifelse pxcor >= -15  and pxcor <= 15 and pycor >= -15 and pycor <= 15
    [ set pcolor blue ]
    [ set pcolor green ]
  ]

  set outside-patches patches with [pcolor = green]
  set supermarket-patches patches with [pcolor = blue]

  ask humans [
    move-to one-of outside-patches
    set food-level 10
    set panic-buying? false
    let num random 5 ;; randomly determine number of close friends & family a human have
    create-links-with n-of num other turtles ;; create the links with other humans
  ]

end

to go
  tick

  set-influenced-factor   ;; social factor – how easily an agent is to be influenced to panic buying (scale: 1-5)
  set-perceived-scarcity   ;; psychological factor – perceived scarcity of an agent (scale: 1-5)
  set-relatives-factor   ;; social factor – number of relatives that are panic buying (scale: 1-5)
  set-radius-factor   ;; social factor – number of agents in its vision radius that are panic buying (scale: 1-5)

  compute-panic-buy-prob

  trigger-panic-buy

  ask humans [ ifelse panic-buying? [set color red ] [set color white ] ]

  move-agents

  check-supermarket


end

;; for moving agents that are NOT in the supermarket (agents on green patch)
to move-agents

  ask humans with [pcolor = green] [

    ;; if agent is in panic buying mode and not in supermarket, food level doesn't decrease. straightaway head towards supermarket.
    ifelse panic-buying? = true [
      ifelse xcor < 0 [
        set xcor xcor + 1
        ifelse ycor < 0 [ set ycor ycor + 1 ] [ set ycor ycor - 1 ]
      ]

      [ set xcor xcor - 1
        ifelse ycor < 0 [ set ycor ycor + 1 ] [ set ycor ycor - 1 ]
      ]
    ]

    ;; if agent is not in panic buying mode, agent moving around as per normal.
    [
      ;; if agent's food level is less than 5 and not in supermarket, agent makes its way towards the supermarket.
      ifelse food-level < 5 [
        ifelse xcor < 0 [
          set xcor xcor + 1
          ifelse ycor < 0 [ set ycor ycor + 1 ] [ set ycor ycor - 1 ]
        ]

        [ set xcor xcor - 1
          ifelse ycor < 0 [ set ycor ycor + 1 ] [ set ycor ycor - 1 ]
        ]
      ]

      ;; if agent's food level is more than or equal to 5, agent moves as per normal randomly on the outside.
      [
        set food-level food-level - 1
        ;; move-to one-of outside-patches
        ;; commented away the above teleporting code for time being
        while [[pcolor] of patch-ahead 1 = blue] [
          rt one-of [0 90 180 270]
        ]
        fd 1   ;; currently each walking step is set to 1
      ]
    ]
  ]

end

;; for moving agents that are in the supermarket (agents on blue patch)
to check-supermarket

  ask humans with [pcolor = blue] [
    set buying-lag-count buying-lag-count + 1

    ;; during first round of buying, agent buys item (2 units if normal, 10 units if panic buy)
    (ifelse buying-lag-count = 1 [

      ;; if agent is panic buying and in supermarket, increase food-level by 10.
      ifelse panic-buying? = true [
        set food-level food-level + 10
        set total-food-bought total-food-bought + 10
        move-to one-of supermarket-patches
      ]

      ;; if agent is not panic buying and in supermarket, increase food-level by 2.
      ;; (try to research if there's any sense on how much more food people buy when they're panic buying vs. normal)
      [ set food-level food-level + 2
        set total-food-bought total-food-bought + 2
      ]

      ]

      ;; during second round of buying, agent doesn't buy as it has already picked up items.
      ;; this is to factor in buffer time for checkout and for agent to roam around supermarket
      ;; for agents that are normal buying – this buffer time allows them to see if other agents are panic buying and influence them to panic buy as well.
      buying-lag-count = 2 [
        ;; move-to one-of supermarket-patches
        ;; commented away the above teleporting code for time being
        while [[pcolor] of patch-ahead 1 = green] [
          rt one-of [0 90 180 270]
        ]
        fd 1   ;; currently each walking step is set to 1

      ]

      ;; during third round of buying, agent checks out and leave supermarket. buying lag count resets
      ;; for agents in panic buy mode, they will go back to non panic buying mode.
      buying-lag-count = 3 [
        move-to one-of outside-patches
        set buying-lag-count 0
        set panic-buying? false
      ]
    )
  ]

end


to compute-panic-buy-prob

  ask humans [

    let social-factors (1 / 3 * ( influenced-factor )  +  1 / 3 * ( relatives-factor ) +  1 / 3 * ( radius-factor ))
    let psychological-factors perceived-scarcity

    ( ifelse

      ;; if normal – affected by relatives & radius factor only
      event-type = "normal" [ set panic-buy-prob 1 / 2 * relatives-factor + 1 / 2 * radius-factor ]

      ;; if rumour – 100% social factors
      event-type = "rumour" [ set panic-buy-prob social-factors ]

      ;; if pandemic – 76.4% social factors 23.6% psychological factors
      event-type = "pandemic" [ set panic-buy-prob 0.764 * social-factors + 0.236 * psychological-factors ]

    )
  ]

end

to set-relatives-factor
  ask humans [
    let total-relatives 0   ;; total number of relatives for that agent
    ask link-neighbors [
      ifelse color = red [
        set num-relatives (num-relatives + 1)
        set total-relatives (total-relatives + 1)
      ][
        set total-relatives (total-relatives + 1)
      ]
    ]
    ifelse total-relatives = 0 [   ;; prevent division by zero
      set relatives-factor 0
    ][
      set relatives-factor ((num-relatives / total-relatives) * 5)   ;; compute relatives-factor, scaled to 5
    ]
  ]
end

to set-radius-factor
  ask humans [
    let total-people 0   ;; total number of people in the vision for that agent
    let panic-people 0
    ask humans in-radius vision-radius [
      ifelse color = red [
        set panic-people (panic-people + 1)
        set total-people (total-people + 1)
      ][
        set total-people (total-people + 1)
      ]
    ]
    ifelse total-people = 0 [
      set radius-factor 0
    ][
      set radius-factor ((panic-people / total-people) * 5)   ;; compute radius-factor, scaled to 5
    ]


  ]
end


;; set the perceived-scarcity based on the paper by Hu
;; perceived-scarcity: how likely an individual will be influenced to panic buy given their perceived scarcity
;; strongly disagree: 25.6% // disagree: 18.7% // neutral: 25.1% // agree: 18.1% // strongly agree: 12.5%
to set-perceived-scarcity
  ask humans [
    let j random 11 / 10
    ( ifelse
      j <= 0.256 [ set perceived-scarcity 1 / 5 ] ;; strongly disagree
      j <= 0.443 [ set perceived-scarcity 2 / 5 ] ;; disagree
      j <= 0.694 [ set perceived-scarcity 3 / 5 ] ;; neutral
      j <= 0.875 [ set perceived-scarcity 4 / 5] ;; agree
      j <= 1 [ set perceived-scarcity 5 / 5 ] ;; strongly agree
    )
  ]
end

;; set the influenced-factor based on the paper by Arafat
;; influence-prob: how likely an individual will be influenced to panic buy by social media posts
;; totally disagree: 32.4% // disagree: 44.6% // neutral: 6.9% // agree: 11.8% // totally agree: 4.3%
to set-influenced-factor
  ask humans [
    let i random 11 / 10
    ( ifelse
      i <= 0.324 [ set influenced-factor 1 / 5 ] ;; totally disagree
      i <= 0.77 [ set influenced-factor 2 / 5] ;; disagree
      i <= 0.839 [ set influenced-factor 3 / 5] ;; neutral
      i <= 0.957 [ set influenced-factor 4 / 5] ;; agree
      i <= 1 [ set influenced-factor 5 / 5] ;; totally agree
    )
  ]
end

to trigger-panic-buy

  ;; only trigger panic buying if humans are not in panic buying mode
  ask humans with [panic-buying? = false] [
    let k random 11 / 10
    ifelse k <= panic-buy-prob [ set panic-buying? true  ] [ set panic-buying? false ]
  ]

end

to-report food-bought-count
  report total-food-bought
end

to-report num-panic-buying
  report count humans with [panic-buying? = true]
end





@#$#@#$#@
GRAPHICS-WINDOW
427
19
1153
746
-1
-1
14.08
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
24
22
90
55
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
100
22
163
55
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
173
23
278
56
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

CHOOSER
27
244
165
289
event-type
event-type
"normal" "rumour" "pandemic"
2

SLIDER
27
71
272
104
human-popln
human-popln
0
200
100.0
5
1
NIL
HORIZONTAL

SLIDER
28
117
200
150
food-consumption
food-consumption
1
10
7.0
1
1
NIL
HORIZONTAL

SLIDER
27
169
199
202
vision-radius
vision-radius
1
20
20.0
1
1
NIL
HORIZONTAL

MONITOR
31
310
283
355
Total Food Bought across Supermarket
food-bought-count
0
1
11

MONITOR
32
374
358
419
Number of Agents that are in Panic Buying Mode
num-panic-buying
0
1
11

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
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
