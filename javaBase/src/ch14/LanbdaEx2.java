package ch14;

@FunctionalInterface
interface MyFunction2 {
    void myMethod();    // public abstract void myMethod();
}

public class LanbdaEx2 {
    public static void main(String[] args) {
        MyFunction2 f = () -> {};
        Object obj = (MyFunction2) (() -> {});
        String str = ((Object) (MyFunction2) (() -> {})).toString();

        System.out.println(f);
        System.out.println(obj);
        System.out.println(str);

//        System.out.println(() -> {});
        System.out.println((MyFunction2) (() -> {}));
        System.out.println(((MyFunction2) (() -> {})).toString());
        System.out.println(((Object) (MyFunction2) (() -> {})).toString());
    }
}
