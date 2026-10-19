package ch14;

import java.util.Arrays;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public class StreamEx4 {
    public static void main(String[] args) {
        Stream<String[]> strArrStrm = Stream.of (
                new String[] {"abc", "def", "jkl"},
                new String[] {"ABC", "GHI", "JKL"}
        );

//        Stream<Stream<String>> strStream = strArrStrm.map(Arrays::stream);
        Stream<String> strStream = strArrStrm.flatMap(Arrays::stream);
        strStream.map(String::toLowerCase)
                .distinct()
                .sorted()
                .forEach(System.out::println);
        System.out.println();

        String[] lineArr = {
                "Believe or not It is true",
                "Do or do not There is no try",
        };

        Stream<String> lineStream = Arrays.stream(lineArr);
        lineStream.flatMap(line -> Stream.of(line.split(" +")))
                .map(String::toLowerCase)
                .distinct()
                .sorted()
                .forEach(System.out::println);
        System.out.println();
    }
}
