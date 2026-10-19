import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.URL;

public class NetworkEx4 {
    public static void main (String args[]) {
        URL url = null;
        BufferedReader input = null;
        String address = "https://shopping.naver.com/gift/home?NaPm=ct%3Dlp9ex0zc%7Cci%3Dshoppingwindow%7Ctr%3Dnsh%7Chk%3D80628418c9e42054c4021801952d856ebb97c1a4%7Ctrx%3D";
        String line = "";

        try {
            url = new URL(address);
            input = new BufferedReader(new InputStreamReader(url.openStream()));
            while ((line=input.readLine()) != null) {
                System.out.println(line);
            }
            input.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
