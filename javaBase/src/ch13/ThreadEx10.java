package ch13;

public class ThreadEx10 implements Runnable{
    static boolean autoSave = false;

    public static void main(String[] args) {
        Thread t = new Thread(new ThreadEx10());
        t.setDaemon(false);
        t.start();

        for (int i=1; i<=10; i++) {
            try {
                Thread.sleep(1000);
            } catch (InterruptedException e) {}
            System.out.println(i);

            if (i==5) {
                autoSave = true;
            }
        }
        System.out.println("프로그램을 종료합니다.");
    }

    public void run() {
        while(true) {   // 무한 루프        // 위으 main 쓰래드가 종료되면 demonThread도 같이 종료
            try {
                Thread.sleep(3 * 1000);
            } catch (InterruptedException e) {}

            if (autoSave) {
                autoSave();
            }
        }
    }

    private void autoSave() {
        System.out.println("작업파일이 자동저장되었습니다.");
    }
}
