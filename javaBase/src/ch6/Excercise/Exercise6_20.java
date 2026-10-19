package ch6.Excercise;

import java.util.Arrays;
import java.util.Random;

public class Exercise6_20 {

    static int[] shuffle(int[] original) {
        int tmp = 0;
        for (int i=0; i<original.length; i++) {
            int j = (int) (Math.random() * 9);
            tmp = original[i];
            original[i] = original[j];
            original[j] = tmp;
        }

        return original;
    }

    public static void main(String[] args) {
        int[] original = {1,2,3,4,5,6,7,8,9};
        System.out.println(Arrays.toString(original));

        int[] result = shuffle(original);
        System.out.println(Arrays.toString(result));
    }

}
