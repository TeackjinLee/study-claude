import java.io.*;
import java.net.*;

public class NetworkEx5 {
    public static void main(String args[]) {
        URL url = null;
        InputStream in = null;
        FileOutputStream out = null;
        String address = "https://github.com/castello/javajungsuk3.git";

        int ch = 0;

        try {
            url = new URL(address);
            in = url.openStream();
            out = new FileOutputStream("https://github.com/castello/javajungsuk3.git");

            while ((ch=in.read()) != -1) {
                out.write(ch);
            }
            in.close();
            out.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
