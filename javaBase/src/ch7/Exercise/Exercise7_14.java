package ch7.Exercise;

class SutdaCard2 {
    final int NUM;
    final boolean IS_KWANG;

    SutdaCard2() {
        this(1, true);
    }

    SutdaCard2(int num, boolean isKwang) {
        this.NUM = num;
        this.IS_KWANG = isKwang;
    }

    public String toString() {
        return NUM + ( IS_KWANG ? "K" : "");
    }
}

public class Exercise7_14 {
    public static void main(String[] args) {
        SutdaCard2 card = new SutdaCard2(1, true);
        System.out.println(card);
    }
}
