class_name PixelArt
extends RefCounted
## Repo-native pixel illustrations. Replace this view layer without touching economy.
const INK := Color("142a30")
const GOLD := Color("edc777")
const CREAM := Color("f4e7c5")
const TEAL := Color("246367")

static func box(canvas: CanvasItem, rect: Rect2, fill: Color, border: Color = INK, line: float = 3.0) -> void:
	canvas.draw_rect(rect, fill)
	canvas.draw_rect(rect, border, false, line)

static func car(canvas: CanvasItem, at: Vector2, color: Color, scale: float = 1.0) -> void:
	var blocks: Array = [[8,18,90,18,color],[25,5,47,18,color],[31,9,17,13,Color("9ac8c5")],[52,9,15,13,Color("6ca6b0")],[1,31,104,8,INK],[15,32,20,16,INK],[76,32,20,16,INK],[21,36,8,8,Color("bdd2ca")],[82,36,8,8,Color("bdd2ca")],[4,23,12,5,GOLD],[90,23,9,6,Color("ffedd4")]]
	for block in blocks:
		canvas.draw_rect(Rect2(at + Vector2(block[0], block[1]) * scale, Vector2(block[2], block[3]) * scale), block[4])

static func house(canvas: CanvasItem, at: Vector2, color: Color, scale: float = 1.0) -> void:
	for block in [[8,13,86,61,color],[0,7,102,8,INK],[15,0,75,9,GOLD],[20,24,22,20,Color("8db9b8")],[52,24,27,20,Color("8db9b8")],[52,52,27,22,INK],[20,53,22,8,GOLD],[0,75,104,6,INK]]:
		canvas.draw_rect(Rect2(at + Vector2(block[0], block[1]) * scale, Vector2(block[2], block[3]) * scale), block[4])

static func coin(canvas: CanvasItem, at: Vector2, scale: float = 1.0) -> void:
	for block in [[-12,-17,24,34,Color("9f7338")],[-17,-12,34,24,Color("9f7338")],[-11,-15,22,29,GOLD],[-15,-10,30,20,GOLD],[-9,-11,18,22,Color("f8dea0")],[-2,-7,4,14,Color("b48744")],[-5,-4,10,3,Color("b48744")],[-5,3,10,3,Color("b48744")]]:
		canvas.draw_rect(Rect2(at + Vector2(block[0], block[1]) * scale, Vector2(block[2], block[3]) * scale), block[4])

static func plant(canvas: CanvasItem, at: Vector2) -> void:
	for block in [[15,33,24,29,Color("bd6d4a")],[11,31,32,7,Color("edb77c")],[25,0,5,36,Color("437968")],[6,6,20,10,Color("5b9275")],[30,0,18,9,Color("70a387")],[31,19,17,8,Color("518971")],[10,22,17,8,Color("70a387")]]:
		canvas.draw_rect(Rect2(at + Vector2(block[0], block[1]), Vector2(block[2], block[3])), block[4])
