package ch14;

import java.util.*;
import java.util.stream.*;

import static java.util.stream.Collectors.*;

public class StreamEx6 {
    public static void main(String[] args) {
        Student[] stuArr = {
                new Student("이자바", 3, 300),
                new Student("김자바", 1, 290),
                new Student("안자바", 2, 100),
                new Student("박자바", 2, 150),
                new Student("소자바", 1, 200),
                new Student("나자바", 3, 290),
                new Student("감자바", 3, 180)
        };

        // 학생 이름만 뽑아서 List<String>에 저장
        List<String> names = Stream.of(stuArr).map(Student::getName).collect(Collectors.toList());
        System.out.println(names);

        // ArrayList로 변환
        ArrayList<String> nameArrayList = Stream.of(stuArr).map(Student::getName).collect(Collectors.toCollection(ArrayList::new));
        System.out.println(nameArrayList);

        // 스트림 배열로 변환
        Student[] stuArr2 = Stream.of(stuArr).toArray(Student[]::new);

        for (Student s : stuArr2) {
            System.out.println(s);
        }

        // 스트림을 Map<String, Student>로 변환, 학생 이름이 key
        Map<String, Student> stuMap = Stream.of(stuArr).collect(Collectors.toMap(s -> s.getName(), s -> s));
        System.out.println(stuMap);

        for (String name : stuMap.keySet()) {
            System.out.println(name + "-" + stuMap.get(name));
        }

        long count = Stream.of(stuArr).collect(counting());
        long totalScore = Stream.of(stuArr).collect(summingInt(Student::getTotalScore));

        System.out.println("count = " + count);
        System.out.println("totalScore = " + totalScore);

        totalScore = Stream.of(stuArr)
                .collect(reducing(0, Student::getTotalScore, Integer::sum));
        System.out.println("totalScore = " + totalScore);

        System.out.println("start");
        Map<String, Integer> studentMap = Stream.of(stuArr).collect(toMap(s -> s.getName(), s -> s.getTotalScore()));
        System.out.println(studentMap);
        System.out.println("end");

        Optional<Student> topStudent = Stream.of(stuArr)
                .collect(maxBy(Comparator.comparingInt(Student::getTotalScore)));
        System.out.println("topStudent = " + topStudent.get());

        IntSummaryStatistics stat = Stream.of(stuArr)
                .collect(summarizingInt(Student::getTotalScore));
        System.out.println(stat);

        String stuNames = Stream.of(stuArr).map(Student::getName).collect(joining(",", "{", "}"));
        System.out.println(stuNames);
    }
}
