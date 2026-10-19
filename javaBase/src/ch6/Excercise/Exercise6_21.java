package ch6.Excercise;

class MyTv {
    boolean isPowerOn;
    int channel;
    int volume;

    final int MAX_VOLUME = 100;
    final int MIN_VOLUME = 0;
    final int MAX_CHANNEL = 100;
    final int MIN_CHANNEL = 1;

    void turnOnOff() {
        isPowerOn = !isPowerOn;
    }

    void volumeUp() {
        volume = volume >= MAX_VOLUME ? MAX_VOLUME : volume + 1;
    }

    void volumeDown() {
        volume = volume >= MIN_VOLUME ? MIN_VOLUME : volume - 1;
    }

    void channelUp() {
        channel = channel > MAX_CHANNEL ? MIN_CHANNEL : channel + 1;
    }

    void channelDown() {
        channel = channel < MIN_CHANNEL ? MAX_CHANNEL : channel - 1;
    }
}

public class Exercise6_21 {
    public static void main(String[] args) {
        MyTv tv = new MyTv();

        tv.channel = 100;
        tv.volume = 0;
        System.out.println("CH : " + tv.channel + ", VOL : " + tv.volume);

        tv.channelDown();
        tv.volumeDown();
        System.out.println("CH : " + tv.channel + ", VOL : " + tv.volume);

        tv.volume = 100;
        tv.channelUp();
        tv.volumeUp();
        System.out.println("CH : " + tv.channel + ", VOL : " + tv.volume);
    }
}
