class_name RadioChannel
extends Resource
## 차 라디오 채널 하나 (docs/06 §라디오). 음악은 RadioSynth가 style대로 코드로 만든다 — 실존 곡·방송국 이름은 쓰지 않는다.
## DJ 말은 소리 대신 화면 아래 자막으로 띄운다 (data/dialogue/lines.csv의 npc = dj, 상황 radio).

@export var id: StringName
@export var display_name := ""           ## 채널 이름 (HUD)
@export var frequency := ""              ## "FM 95.1" 같은 표시
@export var style: StringName = &"kpop"  ## kpop · trot · lofi · rock · news
@export var bpm := 120.0
@export var root := 57                   ## 으뜸음 (MIDI 번호, 57 = A3)
@export var minor := true
@export var seed := 1                    ## 같은 값이면 늘 같은 곡
@export var dj: StringName               ## 자막 대사 npc id (lines.csv)
@export var color := Color(1.0, 0.8, 0.3)
