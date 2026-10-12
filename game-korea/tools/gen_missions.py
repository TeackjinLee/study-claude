#!/usr/bin/env python3
"""미션 .tres 생성기 — data/missions/*.tres의 원본.

미션 60개(갱 3파 × 공중전화 묶음 2 × 10)를 여기서 정의하고 .tres로 쓴다.
지점은 월드 좌표다 (City 상수: BLOCK 576, ROAD 192, PITCH 768). 아래 도우미로 만든다:
  cv(k, seg, t)  세로 도로 k번 오른쪽 갓길, seg번째 블록 줄, 위치 t(0~1)
  ch(k, seg, t)  가로 도로 k번 아래쪽 갓길, seg번째 블록 칸, 위치 t
  sw(i, j, e, t) 블록 (i, j) 인도 (e: 0 위 · 1 오른쪽 · 2 아래 · 3 왼쪽), 위치 t
  center(i, j)   교차로 (i, j)
고친 뒤 실행하고 mission_test를 돌린다 (건물 안·맵 밖·잠긴 구역 지점을 잡는다):
  python3 tools/gen_missions.py data/missions
"""
import math, sys
out = sys.argv[1] if len(sys.argv) > 1 else 'data/missions'
def cv(k,seg,t): return (768*k+170, 192+768*seg+576*t)
def ch(k,seg,t): return (192+768*seg+576*t, 768*k+170)
def sw(i,j,e,t):
    c=[(206+768*i,206+768*j),(754+768*i,206+768*j),(754+768*i,754+768*j),(206+768*i,754+768*j)]
    a=c[e]; b=c[(e+1)%4]
    return (a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t)
def center(i,j): return (768*i+96, 768*j+96)
E=math.pi/2      # 동쪽을 향함 (가로 도로 갓길)
W=-math.pi/2
GOTO,ENTER,DELIVER,KILL,DESTROY,LOSE=range(6)

# 강남
HQ_DOOR=(2510, 2496+576*0.65)
HQ_GARAGE=(2784, 3200)
DOCK=(4320, 3984)
# 종로 건달파 본가 (한옥 (1,-7)) · 홍대 밀수단 아지트 ((-2,-7)) · 여의도 · 변두리 · 공단
JONGNO_DOOR=(974, -4980)
JONGNO_GARAGE=ch(-6,1,0.5)
HONGDAE_DOOR=(-1330, -4980)
HONGDAE_GARAGE=ch(-6,-2,0.5)
YEOUIDO_GARAGE=ch(-2,-3,0.5)
YEOUIDO_DOCK=ch(-1,-3,0.5)
OUTSKIRTS_GARAGE=ch(-9,1,0.5)
PORT=ch(0,-4,0.5)               # 공단 부두 (강가)
SMUGGLER_DOOR=(-1330, 1940)
SMUGGLER_GARAGE=ch(3,-2,0.5)
CAMP_ROAD=ch(-4,-3,0.5)         # 강변북로 캠핑장 앞

VEH={k:'res://data/vehicles/%s.tres'%v for k,v in {
    'porta':'trk_porta','sport':'car_avela_r','sedan':'car_avela','zenith':'car_zenith_g8','striker':'car_striker',
    'rumi':'car_rumi','sonato':'car_sonato','sorea':'car_sorea','taxi':'car_taxi','bike':'etc_bike','bicycle':'etc_bicycle',
    'bongo':'trk_bongo','titan':'trk_titan','tanker':'trk_tanker','mixer':'trk_mixer','village':'bus_village',
    'express':'bus_express','tow':'sp_tow','swat':'sp_swat','bigtruck':'etc_truck','camper':'etc_camper'}.items()}
NPC={k:'res://data/npc/%s.tres'%v for k,v in {
    'oldtown':'gang_oldtown','gangnam':'gang_gangnam','smuggler':'gang_smuggler','boss':'boss','gang_f':'gang_f',
    'assassin':'assassin','thug':'thug'}.items()}

M=[
 dict(id='gangnam_01',tier=0,order=0,title='첫 심부름',reward=30000,respect=8,time=90,
  briefing='신입이라고? 일단 심부름부터 해 봐.\n서쪽 인도에 둔 서류 가방을 본부로 가져와.',
  steps=[dict(kind=GOTO,text='서류 가방을 찾아라',points=[sw(0,2,1,0.5)],radius=40),
         dict(kind=GOTO,text='본부로 가져가라',points=[HQ_DOOR],radius=50)]),
 dict(id='gangnam_02',tier=0,order=1,title='포르타 배달',reward=40000,respect=8,time=40,
  briefing='짐 실은 포르타가 2번 도로에 서 있다.\n물류 창고까지 몰고 가. 트럭 터뜨리면 끝이야.',
  steps=[dict(kind=ENTER,text='포르타 트럭에 타라',points=[cv(2,2,0.6)],headings=[0],vehicle='porta'),
         dict(kind=DELIVER,text='트럭을 물류 창고에 세워라',points=[DOCK],radius=70)]),
 dict(id='gangnam_03',tier=0,order=2,title='수금',reward=45000,respect=8,time=120,
  briefing='가게 세 곳에서 이번 달 몫을 받아 와.\n순서대로 돌아. 늦으면 사장님들이 문 닫는다.',
  steps=[dict(kind=GOTO,text='가게에서 돈 받기 (1/3)',points=[sw(4,3,2,0.5)],radius=40),
         dict(kind=GOTO,text='가게에서 돈 받기 (2/3)',points=[sw(2,4,0,0.5)],radius=40),
         dict(kind=GOTO,text='가게에서 돈 받기 (3/3)',points=[sw(3,1,3,0.5)],radius=40)]),
 dict(id='gangnam_04',tier=0,order=3,title='시운전',reward=50000,respect=8,time=32,
  briefing='새로 들인 아벨라 R 길들이기다.\n체크포인트 여섯 곳을 시간 안에 돌아.',
  steps=[dict(kind=ENTER,text='아벨라 R에 타라',points=[cv(3,3,0.2)],headings=[0],vehicle='sport')]+
        [dict(kind=GOTO,text='체크포인트 (%d/6)'%(n+1),points=[p],radius=90,need_vehicle=True)
         for n,p in enumerate([center(3,2),center(5,2),center(5,4),center(2,4),center(2,3),center(3,3)])]),
 dict(id='gangnam_05',tier=1,order=0,title='제니스 회수',reward=80000,respect=12,time=45,
  briefing='회장님 제니스 G8을 어떤 놈이 몰고 다닌다.\n끌어내리고 본부 차고로 가져와. 흠집 나면 네 월급에서 깐다.',
  steps=[dict(kind=ENTER,text='제니스 G8을 빼앗아라',points=[ch(1,4,0.5)],headings=[E],vehicle='zenith',driver=True),
         dict(kind=DELIVER,text='본부 차고에 세워라 (체력 70% 이상)',points=[HQ_GARAGE],radius=70,min_health=0.7)]),
 dict(id='gangnam_06',tier=1,order=1,title='빚 독촉',reward=70000,respect=12,time=150,
  briefing='건달파 수금책이 우리 구역에서 돈을 걷고 있다.\n일당 셋 다 정리해. 저쪽도 총 들고 있다.',
  steps=[dict(kind=KILL,text='건달파 수금책 일당을 처리해라',npc='oldtown',npc_points=[sw(4,4,0,0.4),sw(4,4,0,0.5),sw(4,4,0,0.6)])]),
 dict(id='gangnam_07',tier=1,order=2,title='트럭 폭파',reward=75000,respect=12,time=150,
  briefing='건달파가 물건 실은 트럭을 연습장 옆에 세워 뒀다.\n통째로 날려 버려. 지키는 놈이 둘 있다.',
  steps=[dict(kind=DESTROY,text='건달파 트럭을 부숴라',points=[ch(1,1,0.5)],headings=[E],vehicle='porta',
              npc='oldtown',npc_points=[(1210,974),(1290,974)])]),
 dict(id='gangnam_08',tier=2,order=0,title='증거 인멸',reward=120000,respect=16,time=180,
  briefing='검찰이 차 세 대를 노린다. 블랙박스에 우리 얼굴이 찍혔어.\n셋 다 고철로 만들어.',
  steps=[dict(kind=DESTROY,text='증거 차량을 부숴라',points=[cv(1,0,0.5),ch(3,4,0.4),cv(5,4,0.7)],headings=[0,E,0],vehicle='sedan')]),
 dict(id='gangnam_09',tier=2,order=1,title='회장 차 습격',reward=130000,respect=16,time=150,
  briefing='건달파 회장이 제니스를 타고 강남을 돈다.\n멈추지 않으니 쫓아가서 부숴.',
  steps=[dict(kind=DESTROY,text='건달파 회장의 제니스를 부숴라',points=[cv(1,2,0.5)],headings=[0],vehicle='zenith',moving=True)]),
 dict(id='gangnam_10',tier=2,order=2,title='검문 돌파',reward=150000,respect=16,time=240,
  briefing='북동쪽 끝에서 물건을 받아 와.\n누가 경찰에 찔렀다. 꼬리 떼고 와라.',
  steps=[dict(kind=GOTO,text='물건을 받아라',points=[sw(5,0,2,0.5)],radius=40),
         dict(kind=LOSE,text='경찰을 따돌려라',wanted=2),
         dict(kind=GOTO,text='본부로 가져가라',points=[HQ_DOOR],radius=50)]),
]

# ── 강남 조직 2묶음: 여의도 공중전화 (3장) ─────────────────────────────
M += [
 dict(id='gangnam_11',gang='gangnam',set=1,tier=0,order=0,title='증권가 서류',reward=110000,respect=8,time=35,
  briefing='여의도에 회장님 서류를 실은 스트라이커가 있다.\n강을 두 번 건너 본부 차고까지. 지름길은 없다.',
  steps=[dict(kind=ENTER,text='스트라이커에 타라',points=[cv(-3,-3,0.3)],headings=[0],vehicle='striker'),
         dict(kind=DELIVER,text='강남 본부 차고에 세워라',points=[HQ_GARAGE],radius=70)]),
 dict(id='gangnam_12',gang='gangnam',set=1,tier=0,order=1,title='방송국 수금',reward=100000,respect=8,time=110,
  briefing='여의도 사람들도 우리한테 빚이 있다.\n세 군데 들러서 봉투 받아 와.',
  steps=[dict(kind=GOTO,text='봉투 받기 (1/3)',points=[sw(-4,-3,2,0.5)],radius=40),
         dict(kind=GOTO,text='봉투 받기 (2/3)',points=[sw(-2,-2,0,0.5)],radius=40),
         dict(kind=GOTO,text='봉투 받기 (3/3)',points=[sw(-2,-3,1,0.4)],radius=40)]),
 dict(id='gangnam_13',gang='gangnam',set=1,tier=0,order=2,title='한강 질주',reward=120000,respect=8,time=45,
  briefing='새 스트라이커 길들이기, 이번엔 한강이다.\n다리 둘을 건너는 코스를 시간 안에 돌아.',
  steps=[dict(kind=ENTER,text='스트라이커에 타라',points=[cv(-3,-3,0.3)],headings=[0],vehicle='striker')]+
        [dict(kind=GOTO,text='체크포인트 (%d/7)'%(n+1),points=[p],radius=90,need_vehicle=True)
         for n,p in enumerate([center(-3,-4),center(0,-4),center(2,-4),center(2,-1),center(2,0),center(5,0),center(5,-4)])]),
 dict(id='gangnam_14',gang='gangnam',set=1,tier=0,order=3,title='정보원 정리',reward=110000,respect=8,time=120,
  briefing='건달파 끄나풀 둘이 여의도에서 우리 얘기를 캐고 다닌다.\n조용히 끝내.',
  steps=[dict(kind=KILL,text='건달파 끄나풀을 처리해라',npc='oldtown',npc_points=[sw(-4,-2,1,0.4),sw(-4,-2,1,0.6)])]),
 dict(id='gangnam_15',gang='gangnam',set=1,tier=1,order=0,title='회장님 세차',reward=160000,respect=12,time=40,
  briefing='회장님 제니스를 여의도 귀빈 주차장으로.\n흠집 하나 없이. 80% 아래로 망가지면 끝이다.',
  steps=[dict(kind=ENTER,text='제니스 G8에 타라',points=[cv(3,2,0.5)],headings=[0],vehicle='zenith'),
         dict(kind=DELIVER,text='여의도 주차장에 세워라 (체력 80% 이상)',points=[YEOUIDO_GARAGE],radius=70,min_health=0.8)]),
 dict(id='gangnam_16',gang='gangnam',set=1,tier=1,order=1,title='종로 사무실 습격',reward=150000,respect=12,time=150,
  briefing='건달파 본가 옆 사무실에 놈들이 모여 있다.\n셋 다 눕혀. 저쪽도 쏜다.',
  steps=[dict(kind=KILL,text='건달파 조직원을 처리해라',npc='oldtown',npc_points=[sw(2,-7,3,0.3),sw(2,-7,3,0.5),sw(2,-7,3,0.7)])]),
 dict(id='gangnam_17',gang='gangnam',set=1,tier=1,order=2,title='유조차 탈취',reward=170000,respect=12,time=60,
  briefing='건달파가 기름을 빼돌린다. 강변북로 유조차를 빼앗아\n여의도 선착장으로. 총 맞으면 크게 터진다.',
  steps=[dict(kind=ENTER,text='유조차를 빼앗아라',points=[ch(-4,1,0.5)],headings=[E],vehicle='tanker',driver=True),
         dict(kind=DELIVER,text='여의도 선착장에 세워라',points=[YEOUIDO_DOCK],radius=80,min_health=0.4)]),
 dict(id='gangnam_18',gang='gangnam',set=1,tier=2,order=0,title='호송차 습격',reward=220000,respect=16,time=200,
  briefing='우리 사람이 특공대 호송차에 실려 간다.\n차를 부숴. 경찰이 벌 떼처럼 올 거다 — 다 떨쳐 내.',
  steps=[dict(kind=DESTROY,text='호송차를 부숴라',points=[cv(1,-7,0.5)],headings=[0],vehicle='swat',moving=True),
         dict(kind=LOSE,text='경찰을 따돌려라',wanted=3)]),
 dict(id='gangnam_19',gang='gangnam',set=1,tier=2,order=1,title='건달파 회장 암살',reward=230000,respect=16,time=200,
  briefing='건달파 회장이 변두리 단골집에서 혼자 나온다.\n총을 차고 다닌다. 끝내고 여의도로 돌아와.',
  steps=[dict(kind=KILL,text='건달파 회장을 처리해라',npc='boss',npc_points=[sw(-2,-10,2,0.5)]),
         dict(kind=GOTO,text='여의도로 돌아와라',points=[(-2098,-1650)],radius=60)]),
 dict(id='gangnam_20',gang='gangnam',set=1,tier=2,order=2,title='여의도 대탈출',reward=250000,respect=16,time=260,
  briefing='금고에서 장부를 꺼내 와. 경보가 울리면 특공대가 온다.\n살아서 본부까지 오면 네가 이 동네 실세다.',
  steps=[dict(kind=GOTO,text='장부를 챙겨라',points=[sw(-2,-2,2,0.5)],radius=40),
         dict(kind=LOSE,text='특공대를 따돌려라',wanted=4),
         dict(kind=GOTO,text='강남 본부로 가져가라',points=[HQ_DOOR],radius=50)]),
]

# ── 구도심 건달파 1묶음: 종로 공중전화 (2장) ───────────────────────────
M += [
 dict(id='oldtown_01',gang='oldtown',set=0,tier=0,order=0,title='시장 심부름',reward=70000,respect=8,time=110,
  briefing='어이 강남 촌놈, 우리 쪽 일도 해 볼래?\n시장 가게 세 곳에 들러서 형님 물건 받아 와.',
  steps=[dict(kind=GOTO,text='물건 받기 (1/3)',points=[sw(2,-7,0,0.5)],radius=40),
         dict(kind=GOTO,text='물건 받기 (2/3)',points=[sw(3,-6,3,0.5)],radius=40),
         dict(kind=GOTO,text='물건 받기 (3/3)',points=[sw(0,-6,1,0.5)],radius=40)]),
 dict(id='oldtown_02',gang='oldtown',set=0,tier=0,order=1,title='포르타 짐',reward=70000,respect=8,time=35,
  briefing='짐 실은 포르타를 홍대 쪽 창고 앞까지.\n밀수단 구역이니 오래 머물지 마.',
  steps=[dict(kind=ENTER,text='포르타에 타라',points=[cv(3,-8,0.6)],headings=[0],vehicle='porta'),
         dict(kind=DELIVER,text='홍대 창고 앞에 세워라',points=[ch(-7,-4,0.5)],radius=70)]),
 dict(id='oldtown_03',gang='oldtown',set=0,tier=0,order=2,title='자릿세',reward=75000,respect=8,time=120,
  briefing='종로 노점 자릿세 걷는 날이다.\n세 곳. 안 내는 놈은 없을 거다.',
  steps=[dict(kind=GOTO,text='자릿세 받기 (1/3)',points=[sw(4,-7,2,0.3)],radius=40),
         dict(kind=GOTO,text='자릿세 받기 (2/3)',points=[sw(5,-8,3,0.6)],radius=40),
         dict(kind=GOTO,text='자릿세 받기 (3/3)',points=[sw(1,-8,1,0.5)],radius=40)]),
 dict(id='oldtown_04',gang='oldtown',set=0,tier=0,order=3,title='골목 레이스',reward=80000,respect=8,time=32,
  briefing='루미로 종로 골목을 한 바퀴.\n좁은 길에서 빠른 놈이 진짜다.',
  steps=[dict(kind=ENTER,text='루미에 타라',points=[cv(1,-7,0.3)],headings=[0],vehicle='rumi')]+
        [dict(kind=GOTO,text='체크포인트 (%d/6)'%(n+1),points=[p],radius=90,need_vehicle=True)
         for n,p in enumerate([center(1,-7),center(4,-7),center(4,-6),center(2,-6),center(2,-5),center(5,-5)])]),
 dict(id='oldtown_05',gang='oldtown',set=0,tier=1,order=0,title='밀수단 앞잡이',reward=110000,respect=12,time=150,
  briefing='밀수단 놈들이 홍대에서 우리 애들을 팬다.\n셋 다 정리해.',
  steps=[dict(kind=KILL,text='밀수단원을 처리해라',npc='smuggler',npc_points=[sw(-3,-6,0,0.3),sw(-3,-6,0,0.5),sw(-3,-6,0,0.7)])]),
 dict(id='oldtown_06',gang='oldtown',set=0,tier=1,order=1,title='봉고르 회수',reward=110000,respect=12,time=35,
  briefing='밀수단이 우리 봉고르를 몰고 다닌다.\n끌어내리고 본가 차고로. 너무 망가뜨리지 마.',
  steps=[dict(kind=ENTER,text='봉고르를 빼앗아라',points=[cv(-3,-7,0.5)],headings=[0],vehicle='bongo',driver=True),
         dict(kind=DELIVER,text='종로 본가 차고에 세워라 (체력 60% 이상)',points=[JONGNO_GARAGE],radius=70,min_health=0.6)]),
 dict(id='oldtown_07',gang='oldtown',set=0,tier=1,order=2,title='강남 기습',reward=120000,respect=12,time=160,
  briefing='강남 놈들 제니스가 다리 건너 주차장에 서 있다.\n지키는 놈 둘. 차를 고철로 만들어.',
  steps=[dict(kind=DESTROY,text='강남 조직 제니스를 부숴라',points=[ch(1,2,0.5)],headings=[E],vehicle='zenith',
              npc='gangnam',npc_points=[(1700,974),(1780,974)])]),
 dict(id='oldtown_08',gang='oldtown',set=0,tier=2,order=0,title='밀수 트럭',reward=150000,respect=16,time=180,
  briefing='밀수단 봉고르 두 대가 홍대를 돈다. 물건째로 날려.\n멈추지 않는다.',
  steps=[dict(kind=DESTROY,text='밀수단 트럭을 부숴라',points=[cv(-3,-8,0.4),cv(-1,-7,0.6)],headings=[0,0],vehicle='bongo',moving=True)]),
 dict(id='oldtown_09',gang='oldtown',set=0,tier=2,order=1,title='경찰서 앞 도발',reward=150000,respect=16,time=220,
  briefing='짭새들한테 우리 얼굴 좀 보여 줘야겠다.\n경찰서 앞에서 소란 피우고, 다 따돌린 다음 본가로 와.',
  steps=[dict(kind=GOTO,text='종로 경찰서 앞으로 가라',points=[(2784,-4622)],radius=50),
         dict(kind=LOSE,text='경찰을 따돌려라',wanted=3),
         dict(kind=GOTO,text='종로 본가로 돌아와라',points=[JONGNO_DOOR],radius=50)]),
 dict(id='oldtown_10',gang='oldtown',set=0,tier=2,order=2,title='캠핑장 습격',reward=160000,respect=16,time=200,
  briefing='밀수단 간부들이 한강 캠핑장에서 고기 굽고 있다.\n넷이다. 하나도 남기지 마.',
  steps=[dict(kind=KILL,text='밀수단 간부를 처리해라',npc='smuggler',
              npc_points=[sw(-3,-5,0,0.3),sw(-3,-5,0,0.5),sw(-3,-5,0,0.7),sw(-3,-5,1,0.3)])]),
]

# ── 구도심 건달파 2묶음: 변두리 공중전화 (3장) ──────────────────────────
M += [
 dict(id='oldtown_11',gang='oldtown',set=1,tier=0,order=0,title='이사 도우미',reward=110000,respect=8,time=30,
  briefing='형님 이삿짐이다. 타이탄 몰고 종로 본가까지.\n짐 떨어뜨리면 너도 떨어진다.',
  steps=[dict(kind=ENTER,text='타이탄에 타라',points=[cv(3,-10,0.5)],headings=[0],vehicle='titan'),
         dict(kind=DELIVER,text='종로 본가 차고에 세워라',points=[JONGNO_GARAGE],radius=80)]),
 dict(id='oldtown_12',gang='oldtown',set=1,tier=0,order=1,title='빌라 수금',reward=100000,respect=8,time=110,
  briefing='빌라촌 사채 이자 받는 날.\n세 집 돌아.',
  steps=[dict(kind=GOTO,text='이자 받기 (1/3)',points=[sw(-1,-11,2,0.5)],radius=40),
         dict(kind=GOTO,text='이자 받기 (2/3)',points=[sw(0,-9,3,0.5)],radius=40),
         dict(kind=GOTO,text='이자 받기 (3/3)',points=[sw(2,-11,2,0.3)],radius=40)]),
 dict(id='oldtown_13',gang='oldtown',set=1,tier=0,order=2,title='마을버스 납치',reward=115000,respect=8,time=25,
  briefing='마을버스 기사가 우리 돈을 안 갚는다.\n버스째 끌고 와.',
  steps=[dict(kind=ENTER,text='마을버스를 빼앗아라',points=[ch(-10,-3,0.5)],headings=[E],vehicle='village',driver=True),
         dict(kind=DELIVER,text='변두리 차고에 세워라',points=[OUTSKIRTS_GARAGE],radius=80)]),
 dict(id='oldtown_14',gang='oldtown',set=1,tier=0,order=3,title='아파트 단지 순찰',reward=115000,respect=8,time=32,
  briefing='배달 오토바이로 단지를 한 바퀴.\n우리 구역이란 걸 보여 줘.',
  steps=[dict(kind=ENTER,text='오토바이에 타라',points=[cv(1,-10,0.3)],headings=[0],vehicle='bike')]+
        [dict(kind=GOTO,text='체크포인트 (%d/6)'%(n+1),points=[p],radius=90,need_vehicle=True)
         for n,p in enumerate([center(1,-11),center(-2,-11),center(-2,-9),center(-5,-9),center(-5,-11),center(-4,-11)])]),
 dict(id='oldtown_15',gang='oldtown',set=1,tier=1,order=0,title='강남 첩자',reward=160000,respect=12,time=160,
  briefing='강남 조직 첩자 셋이 여의도에서 우리 장부를 노린다.\n먼저 쳐.',
  steps=[dict(kind=KILL,text='강남 조직원을 처리해라',npc='gangnam',npc_points=[sw(-3,-2,2,0.3),sw(-3,-2,2,0.5),sw(-3,-2,2,0.7)])]),
 dict(id='oldtown_16',gang='oldtown',set=1,tier=1,order=1,title='다리를 막아라',reward=160000,respect=12,time=65,
  briefing='레미콘으로 강남 다리를 막아 버려.\n다리 한가운데 세우고 튀어.',
  steps=[dict(kind=ENTER,text='레미콘에 타라',points=[cv(4,-10,0.5)],headings=[0],vehicle='mixer'),
         dict(kind=DELIVER,text='다리 한가운데 세워라',points=[cv(2,-3,0.5)],radius=90)]),
 dict(id='oldtown_17',gang='oldtown',set=1,tier=1,order=2,title='여의도 금고',reward=170000,respect=12,time=220,
  briefing='여의도 사무실 금고를 털어. 경보가 울릴 거다.\n경찰 떼어 내고 종로 본가로.',
  steps=[dict(kind=GOTO,text='금고를 털어라',points=[sw(-4,-3,3,0.5)],radius=40),
         dict(kind=LOSE,text='경찰을 따돌려라',wanted=2),
         dict(kind=GOTO,text='종로 본가로 가져와라',points=[JONGNO_DOOR],radius=50)]),
 dict(id='oldtown_18',gang='oldtown',set=1,tier=2,order=0,title='제니스 행렬',reward=220000,respect=16,time=200,
  briefing='강남 간부 둘이 제니스를 타고 여의도를 돈다.\n두 대 다 부숴.',
  steps=[dict(kind=DESTROY,text='강남 간부의 제니스를 부숴라',points=[cv(-2,-3,0.5),cv(-4,-2,0.5)],headings=[0,0],vehicle='zenith',moving=True)]),
 dict(id='oldtown_19',gang='oldtown',set=1,tier=2,order=1,title='강남 창고 털기',reward=220000,respect=16,time=200,
  briefing='강남 물류 창고 앞에 트럭 셋. 지키는 놈들도 셋.\n트럭을 다 날려.',
  steps=[dict(kind=DESTROY,text='강남 조직 트럭을 부숴라',points=[ch(5,5,0.2),ch(5,5,0.5),ch(5,5,0.8)],headings=[E,E,E],vehicle='porta',
              npc='gangnam',npc_points=[sw(5,4,2,0.3),sw(5,4,2,0.5),sw(5,4,2,0.7)])]),
 dict(id='oldtown_20',gang='oldtown',set=1,tier=2,order=2,title='최후의 담판',reward=240000,respect=16,time=220,
  briefing='강남 조직 간부들이 금강개발 앞에 모였다.\n여자들이 더 독하다. 넷 다 끝내.',
  steps=[dict(kind=KILL,text='강남 간부를 처리해라',npc='gang_f',
              npc_points=[sw(3,3,0,0.3),sw(3,3,0,0.5),sw(3,3,0,0.7),sw(3,3,1,0.4)])]),
]

# ── 외곽 밀수단 1묶음: 홍대 공중전화 (2장) ─────────────────────────────
M += [
 dict(id='smuggler_01',gang='smuggler',set=0,tier=0,order=0,title='클럽 배달',reward=70000,respect=8,time=110,
  briefing='새로 왔다며? 홍대 클럽 셋에 물건 돌려.\n뛰어. 수상해 보이지 않게.',
  steps=[dict(kind=GOTO,text='배달 (1/3)',points=[sw(-4,-7,2,0.5)],radius=40),
         dict(kind=GOTO,text='배달 (2/3)',points=[sw(-1,-8,3,0.5)],radius=40),
         dict(kind=GOTO,text='배달 (3/3)',points=[sw(-5,-6,1,0.5)],radius=40)]),
 dict(id='smuggler_02',gang='smuggler',set=0,tier=0,order=1,title='오토바이 퀵',reward=70000,respect=8,time=38,
  briefing='오토바이로 강 건너 강남 클럽까지 소포 하나.\n다리 하나 건너면 된다. 빨리.',
  steps=[dict(kind=ENTER,text='오토바이에 타라',points=[cv(-2,-7,0.7)],headings=[0],vehicle='bike'),
         dict(kind=DELIVER,text='강남 클럽 앞에 세워라',points=[ch(4,3,0.5)],radius=70)]),
 dict(id='smuggler_03',gang='smuggler',set=0,tier=0,order=2,title='강변 픽업',reward=75000,respect=8,time=18,
  briefing='강변북로에 짐 실은 봉고르가 있다.\n아지트 차고로 몰고 와.',
  steps=[dict(kind=ENTER,text='봉고르에 타라',points=[ch(-4,-1,0.4)],headings=[E],vehicle='bongo'),
         dict(kind=DELIVER,text='홍대 아지트 차고에 세워라',points=[HONGDAE_GARAGE],radius=70)]),
 dict(id='smuggler_04',gang='smuggler',set=0,tier=0,order=3,title='자전거 도둑',reward=80000,respect=8,time=18,
  briefing='자전거 탄 놈 가방에 우리 물건이 있다.\n자전거째 빼앗아. 자전거는 아무도 신고 안 한다.',
  steps=[dict(kind=ENTER,text='자전거를 빼앗아라',points=[cv(-4,-6,0.5)],headings=[0],vehicle='bicycle',driver=True),
         dict(kind=DELIVER,text='아지트 차고에 세워라',points=[HONGDAE_GARAGE],radius=60)]),
 dict(id='smuggler_05',gang='smuggler',set=0,tier=1,order=0,title='강남 차 털기',reward=110000,respect=12,time=35,
  briefing='강남 놈들 스트라이커가 다리 건너에 있다.\n빼앗아서 홍대로. 반쯤 망가지면 팔 수가 없다.',
  steps=[dict(kind=ENTER,text='스트라이커를 빼앗아라',points=[cv(4,1,0.5)],headings=[0],vehicle='striker',driver=True),
         dict(kind=DELIVER,text='홍대 아지트 차고에 세워라 (체력 70% 이상)',points=[HONGDAE_GARAGE],radius=70,min_health=0.7)]),
 dict(id='smuggler_06',gang='smuggler',set=0,tier=1,order=1,title='단속반',reward=110000,respect=12,time=160,
  briefing='강남 조직이 우리 판매책을 쫓는다.\n강남 놈들 셋, 오피스텔 앞에 있다.',
  steps=[dict(kind=KILL,text='강남 조직원을 처리해라',npc='gangnam',npc_points=[sw(4,3,3,0.3),sw(4,3,3,0.5),sw(4,3,3,0.7)])]),
 dict(id='smuggler_07',gang='smuggler',set=0,tier=1,order=2,title='택시 위장',reward=120000,respect=12,time=30,
  briefing='택시로 위장해서 물건을 돌린다.\n택시 빼앗아서 정해진 길로 돌아.',
  steps=[dict(kind=ENTER,text='택시를 빼앗아라',points=[cv(-1,-8,0.5)],headings=[0],vehicle='taxi',driver=True)]+
        [dict(kind=GOTO,text='배달 지점 (%d/5)'%(n+1),points=[p],radius=90,need_vehicle=True)
         for n,p in enumerate([center(-1,-5),center(1,-5),center(1,-7),center(3,-7),center(3,-5)])]),
 dict(id='smuggler_08',gang='smuggler',set=0,tier=2,order=0,title='견인소 털기',reward=150000,respect=16,time=220,
  briefing='경찰이 우리 차를 견인해 갔다. 견인차째 훔쳐.\n경찰이 쫓아온다 — 다 떼고 아지트로.',
  steps=[dict(kind=ENTER,text='견인차를 빼앗아라',points=[cv(4,-7,0.5)],headings=[0],vehicle='tow',driver=True),
         dict(kind=LOSE,text='경찰을 따돌려라',wanted=2),
         dict(kind=DELIVER,text='홍대 아지트 차고에 세워라',points=[HONGDAE_GARAGE],radius=70)]),
 dict(id='smuggler_09',gang='smuggler',set=0,tier=2,order=1,title='금강개발 기습',reward=160000,respect=16,time=200,
  briefing='금강개발 정문 앞 강남 놈들 넷.\n강남 한복판이다. 끝내고 바로 빠져.',
  steps=[dict(kind=KILL,text='강남 조직원을 처리해라',npc='gangnam',
              npc_points=[sw(3,2,2,0.3),sw(3,2,2,0.5),sw(3,2,2,0.7),sw(3,2,3,0.6)])]),
 dict(id='smuggler_10',gang='smuggler',set=0,tier=2,order=2,title='다리 추격',reward=160000,respect=16,time=180,
  briefing='강남 회장 제니스가 다리를 건너 종로로 간다.\n강 위에서 끝내.',
  steps=[dict(kind=DESTROY,text='강남 회장의 제니스를 부숴라',points=[cv(2,0,0.5)],headings=[math.pi],vehicle='zenith',moving=True)]),
]

# ── 외곽 밀수단 2묶음: 공단 공중전화 (4장) ─────────────────────────────
M += [
 dict(id='smuggler_11',gang='smuggler',set=1,tier=0,order=0,title='컨테이너 하역',reward=250000,respect=8,time=35,
  briefing='공단 끝에 컨테이너 트럭이 있다.\n부두까지 몰고 가. 크고 무겁다.',
  steps=[dict(kind=ENTER,text='대형 트럭에 타라',points=[cv(-1,4,0.5)],headings=[0],vehicle='bigtruck'),
         dict(kind=DELIVER,text='부두에 세워라',points=[PORT],radius=90)]),
 dict(id='smuggler_12',gang='smuggler',set=1,tier=0,order=1,title='공단 수금',reward=240000,respect=8,time=110,
  briefing='공장 사장들한테 이번 달 보호비.\n세 곳.',
  steps=[dict(kind=GOTO,text='보호비 받기 (1/3)',points=[sw(-4,3,1,0.5)],radius=40),
         dict(kind=GOTO,text='보호비 받기 (2/3)',points=[sw(-1,2,3,0.5)],radius=40),
         dict(kind=GOTO,text='보호비 받기 (3/3)',points=[sw(-5,1,2,0.5)],radius=40)]),
 dict(id='smuggler_13',gang='smuggler',set=1,tier=0,order=2,title='유조차 운반',reward=260000,respect=8,time=30,
  briefing='기름 실은 유조차를 부두로.\n총 맞으면 동네가 날아간다.',
  steps=[dict(kind=ENTER,text='유조차에 타라',points=[cv(-3,4,0.5)],headings=[0],vehicle='tanker'),
         dict(kind=DELIVER,text='부두에 세워라 (체력 50% 이상)',points=[PORT],radius=90,min_health=0.5)]),
 dict(id='smuggler_14',gang='smuggler',set=1,tier=0,order=3,title='레미콘 레이스',reward=250000,respect=8,time=50,
  briefing='공장장들 내기다. 레미콘으로 공단 한 바퀴.\n느리다고? 그래서 재밌는 거다.',
  steps=[dict(kind=ENTER,text='레미콘에 타라',points=[cv(-2,1,0.3)],headings=[0],vehicle='mixer')]+
        [dict(kind=GOTO,text='체크포인트 (%d/5)'%(n+1),points=[p],radius=100,need_vehicle=True)
         for n,p in enumerate([center(-2,0),center(-4,0),center(-4,3),center(-1,3),center(-1,5)])]),
 dict(id='smuggler_15',gang='smuggler',set=1,tier=1,order=0,title='공단 첩자',reward=400000,respect=12,time=160,
  briefing='강남 조직 첩자 셋이 공단에 숨어들었다.\n찾아서 끝내.',
  steps=[dict(kind=KILL,text='강남 조직원을 처리해라',npc='gangnam',npc_points=[sw(-4,4,0,0.3),sw(-3,4,1,0.5),sw(-2,5,0,0.5)])]),
 dict(id='smuggler_16',gang='smuggler',set=1,tier=1,order=1,title='고속버스 털기',reward=400000,respect=12,time=80,
  briefing='고속버스 짐칸에 우리 물건이 실렸다.\n버스째 빼앗아 공단 창고로.',
  steps=[dict(kind=ENTER,text='고속버스를 빼앗아라',points=[ch(-4,2,0.5)],headings=[E],vehicle='express',driver=True),
         dict(kind=DELIVER,text='공단 창고 앞에 세워라',points=[SMUGGLER_GARAGE],radius=90)]),
 dict(id='smuggler_17',gang='smuggler',set=1,tier=1,order=2,title='건달파 트럭',reward=420000,respect=12,time=180,
  briefing='건달파가 공단에 트럭 셋을 세워 놨다. 지키는 놈 둘.\n다 날려.',
  steps=[dict(kind=DESTROY,text='건달파 트럭을 부숴라',points=[ch(4,-4,0.25),ch(4,-4,0.55),ch(4,-4,0.85)],headings=[E,E,E],vehicle='titan',
              npc='oldtown',npc_points=[sw(-4,3,2,0.4),sw(-4,3,2,0.6)])]),
 dict(id='smuggler_18',gang='smuggler',set=1,tier=2,order=0,title='부두 결전',reward=550000,respect=16,time=220,
  briefing='강남 조직이 부두를 빼앗으러 왔다. 암살자까지 데려왔다.\n부두를 지켜.',
  steps=[dict(kind=KILL,text='강남 조직원과 암살자를 처리해라',npc='gangnam',
              npc_points=[sw(-4,0,0,0.2),sw(-4,0,0,0.4),sw(-4,0,0,0.6),sw(-4,0,0,0.8),sw(-5,0,1,0.3)]),
         dict(kind=KILL,text='암살자를 처리해라',npc='assassin',npc_points=[sw(-3,0,0,0.5)])]),
 dict(id='smuggler_19',gang='smuggler',set=1,tier=2,order=1,title='금강개발 선물',reward=560000,respect=16,time=260,
  briefing='유조차를 금강개발 차고 앞까지 몰고 가서 세워.\n그 다음은 네가 알아서. 특공대가 올 거다.',
  steps=[dict(kind=ENTER,text='유조차에 타라',points=[cv(-1,2,0.5)],headings=[0],vehicle='tanker'),
         dict(kind=DELIVER,text='금강개발 차고 앞에 세워라',points=[HQ_GARAGE],radius=80,min_health=0.3),
         dict(kind=LOSE,text='특공대를 따돌려라',wanted=4)]),
 dict(id='smuggler_20',gang='smuggler',set=1,tier=2,order=2,title='서울의 왕',reward=600000,respect=16,time=300,
  briefing='마지막이다. 강남 회장이 부두에 직접 왔다.\n경호원 다 쓸고, 경찰까지 떼고, 아지트로 돌아와.',
  steps=[dict(kind=KILL,text='강남 회장과 경호원을 처리해라',npc='gang_f',
              npc_points=[sw(-5,0,1,0.3),sw(-5,0,1,0.5),sw(-5,0,1,0.7),sw(-4,0,3,0.5)]),
         dict(kind=LOSE,text='경찰을 따돌려라',wanted=3),
         dict(kind=GOTO,text='공단 아지트로 돌아와라',points=[SMUGGLER_DOOR],radius=50)]),
]


def vec(pts): return 'PackedVector2Array(%s)'%', '.join('%g, %g'%(round(x,1),round(y,1)) for x,y in pts)
def esc(s): return s.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')
for m in M:
    ext=[('Script','res://scripts/missions/mission_type.gd'),('Script','res://scripts/missions/mission_step.gd')]
    def eid(kind,path):
        if (kind,path) not in ext: ext.append((kind,path))
        return ext.index((kind,path))+1
    subs=[]
    for n,s in enumerate(m['steps']):
        L=['[sub_resource type="Resource" id="step_%d"]'%n,'script = ExtResource("2")','kind = %d'%s['kind'],'text = "%s"'%esc(s['text'])]
        if 'points' in s: L.append('points = '+vec(s['points']))
        if 'headings' in s: L.append('headings = PackedFloat32Array(%s)'%', '.join('%g'%round(h,4) for h in s['headings']))
        if 'radius' in s: L.append('radius = %g'%s['radius'])
        if s.get('need_vehicle'): L.append('need_vehicle = true')
        if 'vehicle' in s: L.append('vehicle = ExtResource("%d")'%eid('Resource',VEH[s['vehicle']]))
        if s.get('driver'): L.append('driver = true')
        if s.get('moving'): L.append('moving = true')
        if 'npc' in s: L.append('npc = ExtResource("%d")'%eid('Resource',NPC[s['npc']]))
        if 'npc_points' in s: L.append('npc_points = '+vec(s['npc_points']))
        if 'min_health' in s: L.append('min_health = %g'%s['min_health'])
        if 'wanted' in s: L.append('wanted = %d'%s['wanted'])
        subs.append('\n'.join(L))
    head='[gd_resource type="Resource" script_class="MissionType" load_steps=%d format=3]\n\n'%(len(ext)+len(subs)+1)
    head+='\n'.join('[ext_resource type="%s" path="%s" id="%d"]'%(k,p,i+1) for i,(k,p) in enumerate(ext))
    body=['[resource]','script = ExtResource("1")','id = &"%s"'%m['id'],'gang = &"%s"'%m.get('gang','gangnam'),'tier = %d'%m['tier'],]+(['phone_set = %d'%m['set']] if m.get('set',0) else [])+[
          'order = %d'%m['order'],'title = "%s"'%esc(m['title']),'briefing = "%s"'%esc(m['briefing']),
          'reward = %d'%m['reward'],'respect = %d'%m['respect'],'time_limit = %g'%m['time'],
          'steps = Array[ExtResource("2")]([%s])'%', '.join('SubResource("step_%d")'%n for n in range(len(subs)))]
    open('%s/%s.tres'%(out,m['id']),'w').write(head+'\n\n'+'\n\n'.join(subs)+'\n\n'+'\n'.join(body)+'\n')
print('ok', len(M))
