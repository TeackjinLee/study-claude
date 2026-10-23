// tools/gen_motion_index.py가 만든다 — 손으로 고치지 않는다
window.GAME_DIR8 = {
 "version": 1792759797,
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
    },
    "jump_dirs": [
     "s",
     "sw",
     "e",
     "n",
     "ne",
     "w",
     "se"
    ],
    "jump_clips": [
     {
      "name": "jump",
      "col": 0,
      "frames": 22,
      "duration": 1.0,
      "loop": false,
      "takeoff": 7,
      "land": 15,
      "lift": {
       "s": [
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.56,
        3.91,
        7.83,
        11.74,
        13.98,
        13.42,
        9.23,
        3.91,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0
       ],
       "sw": [
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.57,
        4.24,
        8.48,
        12.43,
        14.98,
        14.41,
        10.46,
        4.52,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0
       ],
       "e": [
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.28,
        2.26,
        5.09,
        8.19,
        9.89,
        9.61,
        6.78,
        2.83,
        0.28,
        0.28,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0
       ],
       "n": [
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.28,
        1.96,
        3.08,
        4.75,
        6.99,
        9.78,
        11.74,
        12.02,
        10.34,
        6.43,
        2.52,
        1.12,
        0.84,
        0.84,
        0.56,
        0.28,
        0.28
       ],
       "ne": [
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.13,
        1.7,
        3.4,
        5.95,
        8.79,
        10.77,
        10.77,
        8.79,
        5.1,
        1.42,
        0.57,
        0.28,
        0.0,
        0.0,
        0.28,
        0.28
       ],
       "w": [
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.71,
        4.85,
        7.99,
        10.27,
        9.98,
        6.56,
        2.57,
        0.29,
        0.57,
        0.29,
        0.29,
        0.29,
        0.29,
        0.29
       ],
       "se": [
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.56,
        3.09,
        7.3,
        11.52,
        13.76,
        13.2,
        9.55,
        3.93,
        0.0,
        0.56,
        0.56,
        0.28,
        0.56,
        0.56,
        0.56
       ]
      }
     }
    ],
    "ko_dirs": [
     "s",
     "ne",
     "n",
     "nw",
     "e",
     "sw"
    ],
    "ko_clips": [
     {
      "name": "fall",
      "col": 0,
      "frames": 24,
      "duration": 1.2,
      "loop": false
     },
     {
      "name": "out",
      "col": 24,
      "frames": 16,
      "duration": 3.0,
      "loop": true
     }
    ],
    "ko_head": {
     "s": [
      -27.0,
      -69.0
     ],
     "ne": [
      24.0,
      -70.0
     ],
     "n": [
      25.0,
      -66.0
     ],
     "nw": [
      -27.0,
      -67.0
     ],
     "e": [
      13.0,
      -63.0
     ],
     "sw": [
      -27.0,
      -51.0
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
     "sw",
     "w",
     "nw"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "sw",
     "w",
     "nw"
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
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n"
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
     "se",
     "e",
     "ne",
     "n"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n"
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
     "se",
     "e",
     "ne",
     "n",
     "sw",
     "w",
     "nw"
    ],
    "frames": 12,
    "run_dirs": [
     "s",
     "se",
     "e",
     "ne",
     "n",
     "sw",
     "w",
     "nw"
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
