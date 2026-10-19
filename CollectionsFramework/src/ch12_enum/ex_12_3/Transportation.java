package ch12_enum.ex_12_3;

public enum Transportation implements Fare{

    BUS(100) { public int fare(int distance) {return distance * BASIC_FARE;}},
    TRAIN(150) { public int fare(int distance) {return distance*BASIC_FARE;}},
    SHIP(100) { public int fare(int distance) {return distance*BASIC_FARE;}},
    AIRPLANE(300) { public int fare(int distance) {return distance*BASIC_FARE;}};

    protected final int BASIC_FARE; //  protected로 해야 각상수에서 접근 가능;


    Transportation(int distance) {
        BASIC_FARE = distance;
    }
}
