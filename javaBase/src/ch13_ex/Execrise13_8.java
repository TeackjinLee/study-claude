package ch13_ex;

import java.util.Random;
import java.util.Scanner;
import java.util.Vector;

public class Execrise13_8 {
    Vector words = new Vector<>();
    String[] data = {"태연", "유리", "윤아", "효연", "수영", "서현", "티파니", "써니", "제시카"};

    int interval = 2 * 1000;

    WordGenerator wg = new WordGenerator();

    public static void main(String[] args) {
        Execrise13_8 game = new Execrise13_8();

        game.wg.start();

        Vector words = game.words;

        while (true) {
            System.out.println(words);

            String promt = ">>";
            System.out.print(promt);

            // 화면으로부터 라인단위로 입력받는다.
            Scanner s = new Scanner(System.in);
            String input = s.nextLine().trim();

            int index = words.indexOf(input);

            if (index != -1) {
                words.remove(index);
            }
        }
    }

    class WordGenerator extends Thread {
        public void run() {
            while (true) {
                int rand = (int) (Math.random() * data.length);
                words.add(data[rand]);

                try {
                    Thread.sleep(interval);
                } catch (InterruptedException e) {}
            }
        }
    }

}
