package ch6.Excercise;

public class Exercise6_6 {
    static double getDistance(int x, int y, int x1, int y1) {
        double result = 0;

        double doubleX = (x-x1) * (x-x1);
        double doubleY = (y-y1) * (y-y1);
        result = Math.sqrt(doubleX + doubleY);

        return result;
    }

    public static void main(String[] args) {
        System.out.println(getDistance(1,1,2,2));
    }
}
