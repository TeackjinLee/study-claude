package ch7.Exercise;

class Outer {
    class Inner {
        int iv = 100;
    }

    static class Inner2 {
        int iv = 200;
    }
}
public class Exercise7_25 {
    public static void main(String[] args) {
        Outer outer = new Outer();
        Outer.Inner inner = outer.new Inner();

        Outer.Inner2 inner2 = new Outer.Inner2();
        System.out.println(inner.iv);
        System.out.println(inner2.iv);
    }
}
