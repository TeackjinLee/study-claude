// tools/gen_motion_index.py가 만든다 — 손으로 고치지 않는다
window.GAME_DIR8 = {
 "version": 1792671841,
 "chars": [
  {
   "name": "주인공",
   "scale": 1.0,
   "walk": 110.0,
   "run": 190.0,
   "id": "player",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "n",
     "ne",
     "nw"
    ],
    "frames": 24,
    "run_dirs": [
     "s",
     "se",
     "e",
     "n",
     "nw",
     "ne"
    ],
    "run_frames": 16,
    "turns": [],
    "fall_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "fall_frames": 8,
    "fall_col": 41,
    "punch_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "punch_frames": 12,
    "punch_col": 49,
    "punch_attacks": [
     {
      "name": "jab",
      "col": 0,
      "frames": 15,
      "hit_frame": 9,
      "duration": 0.48
     },
     {
      "name": "straight",
      "col": 15,
      "frames": 15,
      "hit_frame": 4,
      "duration": 0.48
     },
     {
      "name": "uppercut",
      "col": 30,
      "frames": 26,
      "hit_frame": 14,
      "duration": 0.85
     },
     {
      "name": "counter",
      "col": 56,
      "frames": 44,
      "hit_frame": 21,
      "duration": 1.25
     }
    ],
    "attack_dirs": [
     "s",
     "sw",
     "e",
     "nw"
    ],
    "rifle_dirs": [
     "se",
     "e",
     "nw",
     "w"
    ],
    "rifle_clips": [
     {
      "name": "aim",
      "col": 0,
      "frames": 20,
      "duration": 0.84,
      "loop": true
     },
     {
      "name": "fire",
      "col": 20,
      "frames": 8,
      "duration": 0.3,
      "loop": false
     }
    ],
    "rifle_muzzle": {
     "se": [
      41.0,
      -60.5
     ],
     "e": [
      50.0,
      -76.0
     ],
     "nw": [
      -24.9,
      -80.0
     ],
     "w": [
      -39.0,
      -71.0
     ]
    },
    "pistol_dirs": [
     "s",
     "se",
     "e",
     "nw",
     "n",
     "ne",
     "w",
     "sw"
    ],
    "pistol_clips": [
     {
      "name": "aim",
      "col": 0,
      "frames": 1,
      "duration": 1.0,
      "loop": true
     },
     {
      "name": "fire",
      "col": 1,
      "frames": 7,
      "duration": 0.3,
      "loop": false
     },
     {
      "name": "walk",
      "col": 8,
      "frames": 37,
      "duration": 1.54,
      "loop": true
     }
    ],
    "pistol_muzzle": {
     "s": [
      -2,
      -70
     ],
     "se": [
      2,
      -66
     ],
     "n": [
      -6,
      -72
     ],
     "e": [
      42.0,
      -76.0
     ],
     "nw": [
      -21.0,
      -82.0
     ],
     "ne": [
      23.0,
      -81.0
     ],
     "w": [
      -37.0,
      -77.0
     ],
     "sw": [
      -30.0,
      -74.0
     ]
    },
    "rocket_dirs": [
     "s",
     "se",
     "e",
     "nw"
    ],
    "rocket_clips": [
     {
      "name": "aim",
      "col": 0,
      "frames": 24,
      "duration": 2.0,
      "loop": true
     },
     {
      "name": "fire",
      "col": 24,
      "frames": 18,
      "duration": 0.9,
      "loop": false
     }
    ],
    "rocket_muzzle": {
     "s": [
      6.4,
      -68.7
     ],
     "se": [
      21.4,
      -70.9
     ],
     "e": [
      26.2,
      -75.0
     ],
     "nw": [
      -30.7,
      -78.5
     ]
    },
    "rocket_breech": {
     "s": [
      -11.7,
      -79.5
     ],
     "se": [
      -19.9,
      -79.3
     ],
     "e": [
      -21.5,
      -78.0
     ],
     "nw": [
      20.6,
      -77.6
     ]
    }
   }
  },
  {
   "name": "강남 조직원",
   "scale": 1.0,
   "walk": 65.0,
   "run": 175.0,
   "id": "gang_gangnam",
   "meta": {
    "dirs": [],
    "frames": 0,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "강도",
   "scale": 1.0,
   "walk": 67.5,
   "run": 200.0,
   "id": "robber",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "건달파",
   "scale": 1.0,
   "walk": 67.5,
   "run": 175.0,
   "id": "gang_oldtown",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "경찰",
   "scale": 1.0,
   "walk": 64.0,
   "run": 182.0,
   "id": "police",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "경찰 헬기 사수",
   "scale": 1.0,
   "walk": 0.0,
   "run": 0.0,
   "id": "police_heli",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "교통경찰",
   "scale": 1.0,
   "walk": 5.0,
   "run": 170.0,
   "id": "traffic_cop",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "구급대원",
   "scale": 1.0,
   "walk": 70.0,
   "run": 175.0,
   "id": "paramedic",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "군인",
   "scale": 1.0,
   "walk": 77.0,
   "run": 185.0,
   "id": "soldier",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "노숙자",
   "scale": 1.0,
   "walk": 27.0,
   "run": 120.0,
   "id": "homeless",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "도둑",
   "scale": 1.0,
   "walk": 76.0,
   "run": 230.0,
   "id": "thief",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "밀수단원",
   "scale": 1.0,
   "walk": 66.0,
   "run": 185.0,
   "id": "gang_smuggler",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "배달원",
   "scale": 1.0,
   "walk": 70.0,
   "run": 206.0,
   "id": "delivery",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "버스 기사",
   "scale": 1.0,
   "walk": 60.0,
   "run": 160.0,
   "id": "bus_driver",
   "meta": {
    "dirs": [],
    "frames": 0,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "상인",
   "scale": 1.0,
   "walk": 58.0,
   "run": 158.0,
   "id": "merchant",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "소방관",
   "scale": 1.0,
   "walk": 61.0,
   "run": 170.0,
   "id": "firefighter",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "시민 (남성)",
   "scale": 1.0,
   "walk": 58.5,
   "run": 175.0,
   "id": "civ_m",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "시민 (여성)",
   "scale": 1.0,
   "walk": 54.9,
   "run": 170.0,
   "id": "civ_f",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "암살자",
   "scale": 1.0,
   "walk": 73.0,
   "run": 218.0,
   "id": "assassin",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "외국인",
   "scale": 1.0,
   "walk": 51.75,
   "run": 170.0,
   "id": "foreigner",
   "meta": {
    "dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "전단 알바",
   "scale": 0.86,
   "walk": 50.0,
   "run": 170.0,
   "id": "flyer",
   "meta": {
    "dirs": [
     "s",
     "se",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "frames": 8,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "조직 보스",
   "scale": 1.0,
   "walk": 58.0,
   "run": 158.0,
   "id": "boss",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "조직원 (여성)",
   "scale": 1.0,
   "walk": 64.0,
   "run": 182.0,
   "id": "gang_f",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "직장인",
   "scale": 1.0,
   "walk": 54.9,
   "run": 170.0,
   "id": "office",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "특공대",
   "scale": 1.0,
   "walk": 64.0,
   "run": 182.0,
   "id": "swat",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  },
  {
   "name": "폭력배",
   "scale": 1.0,
   "walk": 58.0,
   "run": 158.0,
   "id": "thug",
   "meta": {
    "dirs": [
     "s",
     "sw",
     "w",
     "nw",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "nw",
     "w",
     "sw"
    ],
    "run_frames": 8,
    "turns": []
   }
  }
 ]
};
