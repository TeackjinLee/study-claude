'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

/** 브라우저 Web Speech API (Chrome/Edge 계열). 타입 선언이 없어 필요한 부분만 적는다 */
interface RecognitionResultLike {
  isFinal: boolean;
  0: { transcript: string };
}
interface RecognitionLike {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onresult: ((e: { resultIndex: number; results: ArrayLike<RecognitionResultLike> }) => void) | null;
  onend: (() => void) | null;
  onerror: ((e: { error: string }) => void) | null;
  start(): void;
  stop(): void;
  abort(): void;
}
type RecognitionCtor = new () => RecognitionLike;

function getCtor(): RecognitionCtor | null {
  if (typeof window === 'undefined') return null;
  const w = window as unknown as { SpeechRecognition?: RecognitionCtor; webkitSpeechRecognition?: RecognitionCtor };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

/**
 * 마이크로 말한 내용을 텍스트로 받는다. 확정된 문장은 onFinal 로, 인식 중인 문장은 interim 으로 준다.
 * supported=false 면 버튼을 숨긴다 (Safari/Firefox 등).
 */
export function useSpeechInput(onFinal: (text: string) => void, lang = 'ko-KR') {
  const [supported, setSupported] = useState(false);
  const [listening, setListening] = useState(false);
  const [interim, setInterim] = useState('');
  const [error, setError] = useState<string | null>(null);
  const recRef = useRef<RecognitionLike | null>(null);
  const onFinalRef = useRef(onFinal);
  onFinalRef.current = onFinal;

  useEffect(() => {
    setSupported(getCtor() !== null);
    return () => recRef.current?.abort();
  }, []);

  const stop = useCallback(() => {
    recRef.current?.stop();
  }, []);

  const start = useCallback(() => {
    const Ctor = getCtor();
    if (!Ctor || recRef.current) return;
    const rec = new Ctor();
    rec.lang = lang;
    rec.continuous = true;
    rec.interimResults = true;
    rec.onresult = (e) => {
      let pending = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        if (r.isFinal) onFinalRef.current(r[0].transcript.trim());
        else pending += r[0].transcript;
      }
      setInterim(pending);
    };
    rec.onerror = (e) => {
      // 'no-speech' / 'aborted' 는 정상 종료에 가깝다
      if (e.error !== 'no-speech' && e.error !== 'aborted') {
        setError(e.error === 'not-allowed' ? '마이크 사용이 차단됐습니다. 브라우저 주소창의 권한을 확인하세요.' : `음성 인식 오류: ${e.error}`);
      }
    };
    rec.onend = () => {
      recRef.current = null;
      setListening(false);
      setInterim('');
    };
    recRef.current = rec;
    setError(null);
    setListening(true);
    rec.start();
  }, [lang]);

  const toggle = useCallback(() => (listening ? stop() : start()), [listening, start, stop]);

  return { supported, listening, interim, error, toggle, stop };
}
