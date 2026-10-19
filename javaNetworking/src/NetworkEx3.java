import java.net.*;

public class NetworkEx3 {
    public static void main (String args[]) {
        URL url = null;
        String address = "https://shopping.naver.com/gift/home?NaPm=ct%3Dlp9ex0zc%7Cci%3Dshoppingwindow%7Ctr%3Dnsh%7Chk%3D80628418c9e42054c4021801952d856ebb97c1a4%7Ctrx%3D";

        try {
            url = new URL(address);
            URLConnection conn = url.openConnection();

            System.out.println("conn.toString() : " + conn.getContent());
            System.out.println("getAllowUserInteraction() : " + conn.getAllowUserInteraction());
            System.out.println("getConnectTimeout() : " + conn.getConnectTimeout());
            System.out.println("getContentEncoding() : " + conn.getContentEncoding());
            System.out.println("getContentLength() : " + conn.getContentLength());
            System.out.println("getContentType() : " + conn.getContentType());
            System.out.println("getDate() : " + conn.getDate());
            System.out.println("getAllowUserInteraction() : " + conn.getAllowUserInteraction());
        } catch (Exception e) {
            e.printStackTrace();
        }


    };
}
