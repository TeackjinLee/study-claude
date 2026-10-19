package ch7.Exercise;

public class Exercise7_22 {
    public static void main(String[] args) {
        Circle c = new Circle(10);
        System.out.println("원의 넓이 : " + c.calcArea());

        Retangle r = new Retangle(10, 11);
        r.isSquare();
        System.out.println("사각형 넓이 : " + r.calcArea());
    }
}

class Retangle extends Shape {
    double width;
    double height;

    Retangle(double width, double height) {
        this(new Point(0,0), width, height);
    }

    Retangle(Point p, double width, double height) {
        super(p);
        this.width = width;
        this.height = height;
    }

    @Override
    double calcArea() {
        return width * height;
    }

    void isSquare() {
        if (width == height) {
            System.out.println("정사각형 입니다.");
        } else {
            System.out.println("직사각형입니다.");
        }
    }

}

class Circle extends Shape {
    double r;

    Circle(double r) {
        this(new Point(0,0), r);
    }

    public Circle(Point p, double r) {
        super(p);
        this.r = r;
    }

    @Override
    double calcArea() {
        return r * r * Math.PI;
    }
}

abstract class Shape {
    Point p;

    Shape() {
        this(new Point(0,0));
    }

    Shape(Point p) {
        this.p = p;
    }

    abstract  double calcArea();

    Point getPosition() {
        return p;
    }

    void setPosition(Point p) {
        this.p = p;
    }
}

class Point {
    int x;
    int y;

    Point() {
        this(0,0);
    }

    Point(int x, int y) {
        this.x = x;
        this.y = y;
    }

    public String toString() {
        return "[" + x + ", " + y + "]";
    }
}