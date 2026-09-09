package com.mech.workcalendar;
import org.junit.Test;
import static org.junit.Assert.*;
import java.net.UnknownHostException;

public class SafeWebPolicyTest {
    @Test public void rejectsLocalAndReservedAddresses() throws Exception {
        for (String host : new String[]{"127.0.0.1", "10.0.0.1", "169.254.169.254", "100.64.0.1", "192.168.1.1", "::1", "fc00::1", "224.0.0.1"}) {
            try { SafeWebPlugin.publicAddresses(host); fail("Allowed " + host); }
            catch (UnknownHostException expected) { }
        }
    }
    @Test public void acceptsPublicLiteral() throws Exception {
        assertEquals("8.8.8.8", SafeWebPlugin.publicAddresses("8.8.8.8").get(0).getHostAddress());
    }
}
