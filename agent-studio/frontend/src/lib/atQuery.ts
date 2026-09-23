/** 입력창의 @파일 참조 파싱 (FileMentionMenu가 쓰고, 테스트하기 쉽게 따로 둔다) */

/** 커서 바로 앞의 @검색어 (없으면 null). 이메일 같은 a@b는 빼려고 @ 앞은 공백이나 줄 처음이어야 한다 */
export function atQuery(text: string, caret: number): { start: number; query: string } | null {
  const m = /(^|\s)@([^\s@]*)$/.exec(text.slice(0, caret));
  return m ? { start: caret - m[2].length - 1, query: m[2] } : null;
}
