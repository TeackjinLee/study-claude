package SuggestJenelicClass;

import java.util.ArrayList;

class Fruit2 implements Eatable {

    String result = "Fruit";


    @Override
    public void eatable() {
        System.out.println("냐미");
        result += " Eat";
    }

    public String toString() { return result; }
}
class Apple2 extends Fruit2 {
    @Override
    public void eatable() {
        super.eatable();
        System.out.println(super.result);
    }

    public String toString() { return "Apple";}}
class Grape2 extends Fruit2 { public String toString() {return "Grape";}}
class Toy2 {public String toString() {return "Toy";}};
interface Eatable { public abstract void eatable(); };

public class FruitBoxEx2 {
    // 1.4 제한된 지네릭 클래스
    /**
     * <T extends Fruit> 한종류의 타입만 담을수 있는부분에 Fruit클래스의 자손들만 담을 수 있다는 제한이 더 추가
     */

    public static void main(String[] args) {
        FruitBox<Fruit2> fruitBox = new FruitBox<Fruit2>();
        FruitBox<Apple2> appleBox = new FruitBox<Apple2>();
        FruitBox<Grape2> grapeBox = new FruitBox<Grape2>();
//        FruitBox<Grape2> grapeBox2 = new FruitBox<Apple2>();  //  error, incompatible types
//        FruitBox<Toy2> toyBox = new FruitBox<Toy2>();     // type-variable T

        fruitBox.add(new Fruit2());
        fruitBox.add(new Apple2());
        fruitBox.add(new Grape2());
        appleBox.add(new Apple2());
        fruitBox.get(0).eatable();
//        appleBox.add(new Grape2());     // 에러. Grape는 Apple의 자손이 아님
        grapeBox.add(new Grape2());

        System.out.println("fruitBox-" + fruitBox);
        System.out.println("appleBox-" + appleBox);
        System.out.println("grapeBox-" + grapeBox);
    }
}

class FruitBox<T extends Fruit2 & Eatable> extends Box2<T> {

}

class Box2<T> {
    ArrayList<T> list = new ArrayList<>();
    void add(T item) { list.add(item); }
    T get(int i) { return list.get(i); }
    int size() {return list.size(); }
    public String toString() { return list.toString(); }
}