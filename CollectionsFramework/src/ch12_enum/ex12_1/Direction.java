package ch12_enum.ex12_1;

public enum Direction {
    EAST(1), SOUTH(5), WEST(-1), NORTH(10);

    private final int value;    // 정수를 저장할 필드 (인스턴스 변수)를 추가
    Direction(int value) { this.value = value; }

    public int getValue() { return value; }

}
