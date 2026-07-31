import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.ActivityMonitor;
import Toybox.Position;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

class SunWatchFaceView extends WatchUi.WatchFace {
    private var lastSlowUpdate as Number? = null;
    private var weather as Dictionary = {};
    private var location as Position.Location? = null;

    private var screenWidth as Number, screenHeight as Number;

    //private var showSeconds as Boolean = true;
    
    private const colorDim = 0xFFD3D3D3;
    private const showWeather = true;
    // Moon-phase font glyphs, thinnest waxing crescent (O) to full (H) to
    // thinnest waning crescent (A).
    private const moonPhaseChars = ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O"];

    function initialize() {
        WatchFace.initialize();
        var settings = Toybox.System.getDeviceSettings();
        screenWidth = settings.screenWidth;
        screenHeight = settings.screenHeight;
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.WatchFace(dc));
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        // Get the current time and format it correctly
        var clockTime = System.getClockTime();
        var unix_timestamp = Time.now().value();

        if(clockTime.sec % 60 == 0 or lastSlowUpdate == null or unix_timestamp - lastSlowUpdate >= 60) {
            lastSlowUpdate = unix_timestamp;
            updateWeather();
        }

        adjustPositions();

        if (weather["Temp"] != null and showWeather) {
            var tempData = weather["Temp"].format("%d") + "ª";
            if (weather["WindSpeed"] != null && weather["WindBear"] != null) {
                tempData += weather["WindSpeed"].format("%d") + getWindChar(weather["WindBear"]) ;
            }
            if (weather["Rain"] != null) {
                tempData += weather["Rain"] + "%";
            }
            writeToLED("Weather",tempData);
        }
        var info = ActivityMonitor.getInfo();
        writeToLED("Steps",padNumber(toThousands(info.steps)));
        writeToLED("Floors",padNumber(toThousands(info.floorsClimbed)));

        var notifications = System.getDeviceSettings().notificationCount;
        var notifStr = (notifications > 0) 
            ? toThousands(notifications)
            : "--";
        writeToLED("Notifs",padNumber(notifStr));

        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);
        drawTicks(dc, 3, 5, 2, Math.PI / 6);
        drawSky(dc);
        drawHands(dc, clockTime.hour, clockTime.min, clockTime.sec);
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() as Void {
        //showSeconds = true;
    }

    // Terminate any active timers and prepare for slow updates.
    function onEnterSleep() as Void {
        //showSeconds = false;
        requestUpdate();
    }

    function drawTicks(dc as Dc, width, height, round, jump) {
        var tickBuffer = Graphics.createBufferedBitmap({ :width=>width+3, :height=>height+3});
        var tmpDc = tickBuffer.get().getDc();
        
        tmpDc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        tmpDc.clear();
        tmpDc.setAntiAlias(true);
        tmpDc.setFill(colorDim);
        tmpDc.fillRoundedRectangle(0, 0, width, height, round);

        var transformMatrix = new Graphics.AffineTransform();
        var x = -width/2, y = screenHeight / 2 - height - 5;
        for (var i = 0.0; i < Math.PI * 2; i += jump) {
            var sin = Math.sin(i);
            var cos = Math.cos(i);
            transformMatrix.initialize();
            transformMatrix.translate(x*cos - y*sin, y*cos + x*sin);
            transformMatrix.rotate(i);

            dc.drawBitmap2(screenWidth / 2, screenHeight / 2, tickBuffer, {
                :transform => transformMatrix,
                :filterMode => Graphics.FILTER_MODE_BILINEAR
            });
        }
    }

    function drawHands(dc, clock_hour, clock_min, clock_sec) {
        var bigHandSize = screenWidth/2 - 40;
        var smallHandSize = bigHandSize - 70;

		// Draw the hour hand - convert to minutes then compute angle
        var hour = ( ( ( clock_hour % 12 ) * 60 ) + clock_min ); // hour = 2*60.0;
        hour = hour / (12 * 60.0) * Math.PI * 2 - Math.PI;
        drawHand(dc, hour, 15, smallHandSize, colorDim);

        var min = ( clock_min / 60.0); // min = 40/60.0;
        min = min * Math.PI * 2 - Math.PI;
        drawHand(dc, min, 15, bigHandSize, colorDim);
        
        //if(showSeconds) {
        //    var sec = ( clock_sec / 60.0) *  Math.PI * 2 - Math.PI;
        //    drawHand(dc, sec, 9, bigHandSize, 0xFFF05518);
        //}
    }

    function drawHand(dc, angle, width, height, handColour){
        drawHandBasic(dc, angle, width, height, Graphics.createColor(0x66, 0x00, 0x00, 0x00), 3);
        drawHandBasic(dc, angle, width, height, handColour, 0);
    }

    function drawHandBasic(dc, angle, width, height, handColour, offset){
        var sin = Math.sin(angle);
        var cos = Math.cos(angle);

        var centerOffset = 30;
        var hubWidth = width;
        var hubLength = centerOffset * 2;
        var strokeWidth = 4;

        // Pad the buffer so the stroke's overhang (half the pen width on
        // every side) and the anti-aliasing blend have room to fade into
        // transparency, instead of being hard-clipped at the buffer edge --
        // that clipping is what made the rotated edges look jagged.
        var pad = strokeWidth;
        var half = pad / 2;

        var handBuffer = Graphics.createBufferedBitmap({:width=> width + pad,
                                                        :height=>height + centerOffset + pad});
        var tmpDc = handBuffer.get().getDc();

        tmpDc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        tmpDc.setAntiAlias(true);
        tmpDc.clear();

        // Hollow blade running the full length of the hand
        tmpDc.setColor(handColour, Graphics.COLOR_TRANSPARENT);
        tmpDc.setPenWidth(strokeWidth);
        tmpDc.drawRectangle(half, half, width, height + centerOffset);

        // Solid hub straddling the pivot, drawn on top of the blade
        tmpDc.setFill(handColour);
        tmpDc.fillRectangle(half, half, hubWidth, hubLength);

        var pivotX = half + width / 2;
        var pivotY = half + centerOffset;

        var transformMatrix = new Graphics.AffineTransform();
        transformMatrix.initialize();
        transformMatrix.translate(-pivotX*cos + pivotY*sin, -pivotY*cos - pivotX*sin);
        transformMatrix.rotate(angle);

        dc.drawBitmap2(screenWidth / 2 + offset, screenHeight / 2 + offset, handBuffer, {
            :transform => transformMatrix,
            :filterMode => Graphics.FILTER_MODE_BILINEAR
        });
    }

    function updateWeather() {
        var cc = Weather.getCurrentConditions();
        if (cc != null) {
            var loc = cc.observationLocationPosition;
            var now = Time.now();
            weather["Temp"] = cc.temperature as Number;
            weather["WindBear"] = cc.windBearing as Number;
            weather["WindSpeed"] = cc.windSpeed as Number;
            weather["Rain"] = cc.precipitationChance as Number;
            weather["Night"] = false;
            if (loc != null) {
                location = loc;
                var sunrise = Weather.getSunrise(loc, now);
                var sunset = Weather.getSunset(loc, now);
                if (sunrise.lessThan(now)) { 
                    //if sunrise was already, take tomorrows
                    sunrise = Weather.getSunrise(loc, Time.today().add(new Time.Duration(86401)));
                } else {
                    weather["Night"] = true;
                }
                if (sunset.lessThan(now)) { 
                    //if sunset was already, take tomorrows
                    weather["Night"] = true;
                    sunset = Weather.getSunset(loc, Time.today().add(new Time.Duration(86401)));
                }
                weather["Sunrise"] = sunrise;
                weather["Sunset"] = sunset;
            } else {
                weather["Sunrise"] = null;
                weather["Sunset"] = null;
            }
        }
    }

    // Angle of the sun in the sky: 5*PI/6 at sunrise (upper left), PI/2 at
    // solar noon (top), PI/6 at sunset (upper right) -- standard polar
    // angle, sweeping left to right across the day, then continuing on
    // down and back around to 5*PI/6 across the bottom overnight.
    function getSunAngle() as Float {
        return toSkyAngle(getSunRawAngle());
    }

    // Approximates the moon's position by offsetting the sun's arc by the
    // current lunar phase: at a new moon the offset is 0 (moon tracks the
    // sun), at a full moon it's PI (moon is opposite the sun), etc. This
    // avoids needing a full lunar ephemeris, at the cost of accuracy.
    function getMoonAngle() as Float {
        var raw = getSunRawAngle() + getMoonPhase() * 2 * Math.PI;
        return toSkyAngle(raw);
    }

    // Raw angle in 0..2*PI, with 0 = sunrise, PI = sunset.
    function getSunRawAngle() as Float {
        var loc = location;
        if (loc == null) {
            return Math.PI;
        }

        var now = Time.now();
        var today = Time.today();
        var sunrise = Weather.getSunrise(loc, today);
        var sunset = Weather.getSunset(loc, today);
        if (sunrise == null || sunset == null) {
            return Math.PI;
        }

        if (now.lessThan(sunrise)) {
            var prevSunset = Weather.getSunset(loc, today.subtract(new Time.Duration(86400)));
            return (prevSunset == null) ? Math.PI : arcAngle(now, prevSunset, sunrise, Math.PI, 2 * Math.PI);
        } else if (now.lessThan(sunset)) {
            return arcAngle(now, sunrise, sunset, 0.0, Math.PI);
        } else {
            var nextSunrise = Weather.getSunrise(loc, today.add(new Time.Duration(86400)));
            return (nextSunrise == null) ? Math.PI : arcAngle(now, sunset, nextSunrise, Math.PI, 2 * Math.PI);
        }
    }

    // Fraction of the way through the current lunar cycle, 0..1 (0 = new moon).
    function getMoonPhase() as Float {
        var knownNewMoon = Gregorian.moment({:year=>2000, :month=>1, :day=>6, :hour=>18, :minute=>14});
        var synodicMonthSeconds = 29.530588853 * 86400;
        var elapsed = Time.now().subtract(knownNewMoon).value().toFloat();
        var cycles = elapsed / synodicMonthSeconds;
        return cycles - Math.floor(cycles);
    }

    // Selects the moon-phase glyph (A..O) for the current lunar phase: O is
    // the thinnest waxing crescent (phase just after 0), H is full moon
    // (phase 0.5), and A is the thinnest waning crescent (phase just before
    // the next new moon) -- so the glyph index runs opposite to phase.
    function getMoonPhaseChar() as String {
        var phase = getMoonPhase();
        var lastIndex = moonPhaseChars.size() - 1;
        var idx = Math.round(lastIndex * (1 - phase)).toNumber();
        if (idx < 0) {
            idx = 0;
        } else if (idx > lastIndex) {
            idx = lastIndex;
        }
        return moonPhaseChars[idx];
    }

    // Linear interpolation of `now` between `start` and `end`, mapped from
    // startAngle to endAngle.
    function arcAngle(now as Time.Moment, start as Time.Moment, end as Time.Moment, startAngle as Float, endAngle as Float) as Float {
        var frac = (now.value() - start.value()).toFloat() / (end.value() - start.value());
        return startAngle + frac * (endAngle - startAngle);
    }

    // Converts a raw 0..2*PI angle (0 = rise, PI = set) to a standard polar
    // angle, with rise/set remapped from PI/0 to 5*PI/6 / PI/6 (i.e. the sun
    // and moon stay within the upper part of the circle instead of touching
    // the horizontal edges), wrapped to (-PI..PI].
    function toSkyAngle(raw as Float) as Float {
        while (raw >= 2 * Math.PI) { raw -= 2 * Math.PI; }
        while (raw < 0) { raw += 2 * Math.PI; }

        var riseAngle = 5 * Math.PI / 6;
        var setAngle = Math.PI / 6;

        var angle;
        if (raw <= Math.PI) {
            // day: raw 0..PI -> riseAngle..setAngle
            angle = riseAngle + (raw / Math.PI) * (setAngle - riseAngle);
        } else {
            // night: raw PI..2*PI -> setAngle..(riseAngle - 2*PI)
            var t = (raw - Math.PI) / Math.PI;
            angle = setAngle + t * ((riseAngle - 2 * Math.PI) - setAngle);
        }

        while (angle > Math.PI) { angle -= 2 * Math.PI; }
        while (angle <= -Math.PI) { angle += 2 * Math.PI; }
        return angle;
    }

    function getWindChar(windBear as Number) as String {
        var aux = (windBear + 23) % 360;
        if (aux < 45) { return "e"; }
        if (aux >= 45 && aux < 90) { return "f"; }
        if (aux >= 90 && aux < 135) { return "g"; }
        if (aux >= 135 && aux < 180) { return "h"; }
        if (aux >= 180 && aux < 225) { return "a"; }
        if (aux >= 225 && aux < 270) { return "b"; }
        if (aux >= 270 && aux < 315) { return "c"; }
        if (aux >= 315 && aux < 360) { return "d"; }
        return "-";
    }

    function writeToLED(fieldId as String, value as String) {
        var mask = "";
        for (var i = 0; i < value.length(); i++) { mask += "$"; }
        (View.findDrawableById(fieldId + "Bg") as Text).setText(mask);
        (View.findDrawableById(fieldId) as Text).setText(value);
    }

    function toThousands(nbr as Number?) as String {
        var res;
        if (nbr == null) {
            res = "--";
        } else if (nbr >= 1000) {
            res = (nbr / 1000).toString() + "." + ((nbr % 1000) / 100).toString() + "k";
        } else {
            res = nbr.toString();
        }
        return res;
    }

    function padNumber(nbr as String) {
        return nbr.length() < 2 ? "0" + nbr : nbr;
    }

    function adjustPositions() {
        var leds = ["Notifs", "Steps", "Floors"];
        for (var i=0; i < leds.size(); i++) {
            adjustLedVal(leds[i]);
        }
    }

    function adjustLedVal(name as String) {
        var ledStep = 18;
        if (View.findDrawableById(name + "Label") != null) {
            var label = View.findDrawableById(name + "Label") as Text;
            var bg = View.findDrawableById(name + "Bg") as Text;
            var val = View.findDrawableById(name) as Text;
            bg.setLocation(label.locX, label.locY + ledStep);
            val.setLocation(label.locX, label.locY + ledStep);
        }
    }

    function drawSky(dc as Dc) as Void {
        var sun_angle = getSunAngle();
        var moon_angle = getMoonAngle();
        var is_day = (sun_angle > 0 and sun_angle < Math.PI);
        var sun = View.findDrawableById("Sun") as Bitmap;
        var moon = View.findDrawableById("Moon") as Text;
        var sky_sun = View.findDrawableById("SkySun") as Bitmap;
        var sky_night = View.findDrawableById("SkyNight") as Bitmap;
        var radius = 173;
        
        if (is_day) {
            var sin = Math.sin(sun_angle);
            var cos = Math.cos(sun_angle);

            var half = 45 / 2.0;
            var x = screenWidth / 2 + radius * cos - half;
            var y = screenHeight / 2 - radius * sin - half;
            
            sun.setLocation(x, y);
        } 
        if (moon_angle > 0 and moon_angle < Math.PI) {
            var sin = Math.sin(moon_angle);
            var cos = Math.cos(moon_angle);
            
            var half = 45 / 2.0;
            var x = screenWidth / 2 + radius * cos - half;
            var y = screenHeight / 2 - radius * sin - half;
            
            moon.setLocation(x, y);
            moon.setVisible(true);
            moon.setText(getMoonPhaseChar());
        } else {
            moon.setVisible(false);
        }
        sky_sun.setVisible(is_day);
        sky_night.setVisible(!is_day);
        sun.setVisible(is_day);
    }

}
