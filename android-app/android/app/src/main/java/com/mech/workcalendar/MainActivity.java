package com.mech.workcalendar;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(android.os.Bundle savedInstanceState) {
        registerPlugin(SafeWebPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
