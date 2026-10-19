package ch13;

import java.util.ArrayList;

public class ThreadWaitEx3 {
    public static void main(String[] args) throws Exception {
        ch13.Table table = new ch13.Table(); // 여러 쓰레드가 공유하는 객체

        new Thread(new ch13.Cook(table), "COOK1").start();

        new Thread(new ch13.Customer(table, "donut"), "CUST1").start();
        new Thread(new ch13.Customer(table, "burger"), "CUST2").start();

        Thread.sleep(2000);
        System.exit(0);
    }
}

class Customer implements Runnable {
    private ch13.Table table;
    private String food;

    Customer(ch13.Table table, String food) {
        this.table = table;
        this.food = food;
    }

    public void run() {
        while (true) {
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {}

            String name = Thread.currentThread().getName();
            table.remove(food);
            System.out.println(name + " ate a " + food);
//            if (eatFood()) {
//                System.out.println(name + " ate a " + food);
//            } else {
//                System.out.println(name + " failed to eat. : (");
//            }
        }


    }
//    boolean eatFood() {return table.remove(food); }
}

class Cook implements Runnable {
    private ch13.Table table;

    Cook(ch13.Table table) {
        this.table = table;
    }

    public void run() {
        while (true) {
            // 임의의 요리를 하나 선택해서 table에 추가한다.
            int idx = (int) (Math.random() * table.dishNum());
            table.add(table.dishNames[idx]);

            try {
                Thread.sleep(10);
            } catch (InterruptedException e) {}
        }
    }
}

class Table {
    String[] dishNames = {"donut", "donut", "burger"};
    final int MAX_FOOD = 6;

    private ArrayList<String> dishes = new ArrayList<>();

    public synchronized void add(String dish) { // synchronized 추가
        // 테이블에 음식이 가득찼으면, 테이블에 음식을 추가하지 않는다.
        if(dishes.size() >= MAX_FOOD)
            return;
        dishes.add(dish);
        System.out.println("Dishes : " + dishes.toString());
    }

    public boolean remove(String dishName) {
        synchronized (this) {
            String name = Thread.currentThread().getName();
            while (dishes.size() == 0) {

                System.out.println(name + " is waiting.");
                try {
                    wait();
                    Thread.sleep(500);
                } catch (InterruptedException e) {}
            }
            while (true) {
                for (int i=0; i<dishes.size(); i++) {
                    if (dishName.equals(dishes.get(i))) {
                        dishes.remove(i);
                        notify();
                        return true;
                    }
                }

                try {
                    System.out.println(name + " is waiting.");
                    wait();
                    Thread.sleep(500);
                }  catch (InterruptedException e) {}
            }
        }
    }
    public int dishNum() { return  dishNames.length; }
}