package ch6.Excercise;

import java.util.Arrays;
import java.util.Random;

public class Exercise6_23 {

    static int max(int[] data) {

        if (data == null || data.length == 0) {
            return -99999;
        }

        int max = data[0];

        for (int i=1; i<data.length; i++) {
            if(data[i] > max) {
                max = data[i];
            }
        }

        return max;

    }

    public static void main(String[] args) {
        int[] data = {3,2,9,4,7};
        System.out.println(Arrays.toString(data));
        System.out.println("최대값 : " + max(data));
        System.out.println("최대값 : " + max(null));
        System.out.println("최대값 : " + max(new int[]{}));
    }
}
