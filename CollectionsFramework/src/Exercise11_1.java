import java.util.*;

public class Exercise11_1 {
    public static void main(String[] args) {
        ArrayList list1 = new ArrayList();
        ArrayList list2 = new ArrayList();
        ArrayList kyo = new ArrayList();
        ArrayList cha = new ArrayList();
        ArrayList hap = new ArrayList();

        list1.add(1);
        list1.add(2);
        list1.add(3);
        list1.add(4);

        list2.add(3);
        list2.add(4);
        list2.add(5);
        list2.add(6);

//        list1.stream().filter(i->list2.contains(i)).collect(Collectors.toList());
//        list1.forEach(i -> {
//            if (list2.contains(i)) {
//                kyo.add(i);
//            }
//        });

        kyo.addAll(list1);
        kyo.retainAll(list2);

//        list1.forEach(i -> {
//            if (!list2.contains(i)) {
//                cha.add(i);
//            }
//        });

        cha.addAll(list1);
        cha.removeAll(list2);

//        Set set = new HashSet();
//        set.addAll(list1);
//        set.addAll(list2);
//        hap.addAll(set);
        hap.addAll(list1);
        hap.removeAll(list2);
        hap.addAll(list2);

//       Map<String, ArrayList<String>> map = new HashMap<>();
//       ArrayList list = new ArrayList();
//        list.add(1);
//        list.add("s");
//       map.put("test",list);
//       map.put("test2", list);
//       System.out.println(map.hashCode());

        System.out.println("list1=" + list1);
        System.out.println("list2=" + list2);
        System.out.println("kyo=" + kyo);
        System.out.println("cha=" + cha);
        System.out.println("hap=" + hap);
    }
}
