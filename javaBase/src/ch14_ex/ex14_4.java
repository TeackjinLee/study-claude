package ch14_ex;

import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import java.util.stream.Stream;

public class ex14_4 {
    public static void main(String[] args) {
        Stream<Integer> die = IntStream.rangeClosed(1, 6).boxed();

        die.flatMap(i -> Stream.of(1,2,3,4,5,6).map(i2 -> new int[] {i, i2}))
                .filter(iArr -> iArr[0] + iArr[1] == 6)
                .forEach(iArr -> System.out.println(Arrays.toString(iArr)));

        String[] strArr = {"aaa", "bb", "ccccccc", "dddd"};
        Stream<String> strStream = Stream.of(strArr);
//        int sum = strStream.mapToInt(s -> s.length()).sum();
        int sum = strStream.mapToInt(String::length).sum();
        System.out.println("sum = " + sum);

        Stream<String> strStream2 = Stream.of(strArr);

//        strStream2.map(String::length)
//                .sorted(Comparator.reverseOrder())
//                .limit(1)
//                .forEach(System.out::println);
        int max = strStream2.mapToInt(String::length).max().getAsInt();
        System.out.println("max = " + max);
    }
}
