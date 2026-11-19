import math, random
W, H = 46, 30
g = [['.' for _ in range(W)] for _ in range(H)]
def disc(cx, cy, rx, ry):
    for y in range(H):
        for x in range(W):
            if ((x-cx)/rx)**2 + ((y-cy)/ry)**2 <= 1: g[y][x] = ':'
def path(pts, r):
    for (x0,y0),(x1,y1) in zip(pts, pts[1:]):
        n = int(max(abs(x1-x0), abs(y1-y0))*3)+1
        for i in range(n+1):
            t=i/n; disc(x0+(x1-x0)*t, y0+(y1-y0)*t, r, r*0.8)
# square, a curving main street from the south-west, a lane north-east, an alley east
disc(22, 13, 7.5, 4.2)
path([(1,27),(5,25),(9,21),(12,17),(16,14)], 2.0)
path([(27,11),(31,8),(33,5),(36,2),(38,0)], 1.6)
path([(28,15),(32,17),(36,18),(41,20),(45,21)], 1.5)
path([(18,16),(18,20),(20,24),(22,29)], 1.3)  # narrow alley south
random.seed(4)
for y in range(H):  # ragged edges: grass bites and stray stones
    for x in range(W):
        if g[y][x]==':' and random.random()<0.05: g[y][x]='.'
props = {
 # buildings, bottom-centre tile
 (12,8):'a', (21,7):'b', (31,4):'E', (6,16):'C', (38,12):'F', (30,25):'D', (24,22):'f', (44,17):'g', (13,21):'U', (12,21):'X', (31,20):'U', (23,23):'X', (8,11):'X', (11,24):'d', (40,26):'e', (3,9):'c',
 # town things
 (16,11):'O', (27,12):'M', (25,11):'P', (14,9):'X', (15,9):'U', (24,8):'U', (26,8):'X', (33,14):'Q',
 (19,11):'l', (26,16):'l', (9,18):'l', (34,19):'l', (21,13):'L', (18,14):'N', (29,9):'Z', (8,10):'U',
 (35,15):'X', (36,15):'U', (13,21):'X',
 # greenery
 (1,2):'T', (44,4):'T', (2,20):'T', (44,10):'T', (24,26):'T', (35,27):'T', (16,26):'T',
}
for (x,y),c in props.items(): g[y][x]=c
g[27][41]='C'  # command table, out of the way
for x in range(W):
    for y in (0,):
        if g[y][x]=='.' and random.random()<0.5: g[y][x]='t'
hdr = """# Art mockup (not used by the game): Hollowmark-like streets with houses at varied angles,
# for comparing layouts. Shown with: tools/shot.gd -- scene=town map=mockup_town
@name Mockup
@ground town
@propa mk_house_a
@propb mk_house_b
@propc mk_house_c_f
@propd mk_house_d
@prope mk_house_c
@propC mk_corner_a
@propD mk_corner_b_f
@propE mk_corner_c
@propF mk_corner_d_f
@propf mk_house_a
@propg mk_corner_c_f
@propO well
@propM stall
@propP produce
@propX crates
@propU barrels
@propN bench
@propQ cart
@propZ noticeboard
@propl lamppost
@markK table
@markL lamp
@dirt OMPXUNQZlLK
---
"""
g[27][41]='K'
open('/home/user/last-ink/maps/mockup_town.txt','w').write(hdr + '\n'.join(''.join(r) for r in g) + '\n')
print('\n'.join(''.join(r) for r in g))
