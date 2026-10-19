package ch7.Exercise;

class SutdaDeck {
    final int CARD_NUM = 20;
    SutdaCard[] cards = new SutdaCard[CARD_NUM];

    SutdaDeck() {
        for (int i=0; i<CARD_NUM; i++) {
            if (i == 2 || i==7)  {
                cards[i] = new SutdaCard(i + 1, true);
            } else if (i == 0) {
                cards[i] = new SutdaCard();
            } else {
                cards[i] = new SutdaCard((i % 10) + 1, false);
            }
        }
    }

    public SutdaCard pick(int index) {
        return cards[index];
    }

    public SutdaCard pick() {
        int index = (int) ((Math.random() * CARD_NUM));
        return pick(index);
    }

    public void shuffle() {
        SutdaCard tmp = null;
        for (int i=0; i<CARD_NUM; i++) {
            int j = (int) ((Math.random() * CARD_NUM));
            tmp = cards[j];
            cards[j] = cards[i];
            cards[i] = tmp;
        }
    }
}

class SutdaCard {
    final int num;
    final boolean isKwang;

    SutdaCard() {
        this(1, true);
    }

    SutdaCard(int num, boolean isKwang) {
        this.num = num;
        this.isKwang = isKwang;
    }

    public String toString() {
        return num + (isKwang ? "K" : "");
    }
}

public class Exercise7_1 {
    public static void main(String[] args) {
        SutdaDeck deck = new SutdaDeck();
        // 7_1
//        for (int i=0; i<deck.cards.length; i++) {
//            System.out.print(deck.cards[i] + ", ");
//        }
        // 7_2
        System.out.println(deck.pick(0));
        System.out.println(deck.pick());
        deck.shuffle();

        for (int i=0; i<deck.cards.length; i++) {
            System.out.print(deck.cards[i] + ", ");
        }

        System.out.println();
        System.out.println(deck.pick(0));
    }
}
