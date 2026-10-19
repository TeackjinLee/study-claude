package ch13_ex;

public class Exercose13_1 {
    public static void main(String[] args) {
//        Runnable r = new Thread1();
//        r.run();

        Thread th1 = new Thread(new Thread1());
        th1.start();
    }
}

//class Thread1 extends Thread {
//    public void run() {
//        for (int i=0; i<300; i++) {
//            System.out.print('-');
//        }
//    }
//}

class Thread1 implements Runnable {
    @Override
    public void run() {
        for (int i=0; i<300; i++) {
            System.out.print('-');
        }
    }
}