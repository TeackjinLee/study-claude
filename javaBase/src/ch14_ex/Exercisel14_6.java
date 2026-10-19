package ch14_ex;

import java.util.Random;

public class Exercisel14_6 {
    public static void main(String[] args) {
        new Random().ints(1, 46)
                .distinct()
                .limit(6)
                .sorted()
                .forEach(System.out::println);

        double random = Math.random();

        System.out.println("sss");
        System.out.println((int) (random * 6) + 1);
    };
}
