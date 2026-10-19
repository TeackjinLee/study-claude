package ch6.Excercise;

public class Student {
    // Field
    private String name;
    private int ban;
    private int no;
    private int kor;
    private int eng;
    private int math;

    Student(String name, int ban, int no, int kor, int eng, int math) {
        this.name = name;
        this.ban = ban;
        this.no = no;
        this.kor = kor;
        this.eng = eng;
        this.math = math;
    }

    // getter
    public String getName() {
        return this.name;
    }

    public int getBan() {
        return this.ban;
    }

    public int getNo() {
        return this.no;
    }

    public int getKor() {
        return this.kor;
    }

    public int getEng() {
        return this.eng;
    }

    public int getMath() {
        return this.math;
    }

    public int getTotal() {
        return this.kor + this.eng + this.math;
    }

    public double getAverage() {
        return (double) (int) ((getTotal() / 3.0) * 10 + 0.5) / 10;
    }

    public String toString() {
        return getName() + ", "
                + getBan() + ", "
                + getNo() + ", "
                + getKor() + ", "
                + getEng() + ", "
                + getEng();
    }




}
