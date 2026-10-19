package ch7.Exercise;

public class Exercise7_19 {
    public static void main(String[] args) {
        Buyer b = new Buyer();
        b.buy(new Tv());
        b.buy(new Computer());
        b.buy(new Tv());
        b.buy(new Audio());
        b.buy(new Computer());
        b.buy(new Computer());
        b.buy(new Computer());

        b.summary();
    }
}

class Buyer {
    int money = 1000;
    Product[] cart = new Product[3];
    int i = 0;

    void buy(Product p) {
        // 1. 가진 돈과 물건의 가격을 비교해서 가진돈이 적으면 메서드를 종료한다.
        if (money < p.price) {
            System.out.println("잔액이 부족하여 " + p + "을/를 살수 없습니다.");
            return;
        } else {
            // 2. 가진돈이 충분하면, 제품의 가격을 가진 돈에서 뺴고
            money -= p.price;
            // 3. 장바구니에 구입한 물건을 담는다.
            add(p);
        }

    }

    void add(Product p) {
        if (i >= cart.length) {
            Product[] change_cart = new Product[cart.length * 2];
            System.arraycopy(cart, 0, change_cart, 0, cart.length);
            cart = change_cart;
        }

        cart[i++] = p;
    }

    void summary() {
        String itemList = "";
        int sum = 0;

        for(int i=0; i<cart.length; i++) {
            if (cart.length - 1 != i) {
                itemList += cart[i].toString() + ", ";
            } else {
                itemList += cart[i].toString();
            }

            sum += cart[i].price;
        }

        System.out.println("구입한 물건 : " + itemList);
        System.out.println("사용한 금액 : " + sum);
        System.out.println("남은 금액 : " + money);
    }
}

class Product {
    int price;

    Product(int price) {
        this.price = price;
    }
}

class Tv extends Product {
    Tv() {
        super(100);
    };

    public String toString() {
        return "Tv";
    }
}

class Computer extends Product {
    Computer() {
        super(200);
    }

    public String toString() {
        return "Computer";
    }
}

class Audio extends Product {
    Audio() {
        super(50);
    }

    public String toString() {
        return "Audio";
    }
}

