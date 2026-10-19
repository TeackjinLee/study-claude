import java.util.*;

class BanNoAscending implements Comparator {
    public int compare(Object o1, Object o2) {
        Student s1 = (Student) o1;
        Student s2 = (Student) o2;
        if (s1 instanceof Student && s2 instanceof Student) {
            System.out.println("s1 : " + s1);
            System.out.println("s2 : " + s2);
            return (s1.ban - s2.ban) * 10 + (s1.no - s2.no);
        }
        return -1;
    }
}

class Exercise11_7 {
    public static void main (String[] args) {
        ArrayList list = new ArrayList();
        list.add(new Student("이자바",2,1,70,90,70));
        list.add(new Student("안자바",2,2,60,100,80));
        list.add(new Student("홍길동",1,3,100,100,100));
        list.add(new Student("남궁성",1,1,90,70,80));
        list.add(new Student("김자바",1,2,80,80,90));

        Collections.sort(list, new BanNoAscending());

        Iterator it = list.iterator();

        while (it.hasNext()) {
            System.out.println(it.next());
        }

    }
}
