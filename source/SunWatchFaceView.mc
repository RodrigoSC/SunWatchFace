import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.ActivityMonitor;
import Toybox.Time;

class SunWatchFaceView extends WatchUi.WatchFace {
    private var lastSlowUpdate as Number? = null;
    private var watch_data as WatchData = new WatchData();
    private var moonFont as WatchUi.FontResource?;
    private var sunBitmap as Graphics.BitmapType?;

    private var screenWidth as Number, screenHeight as Number;

    //private var showSeconds as Boolean = true;

    private const colorDim = 0xD3FFFFFF;
    private const showWeather = true;
    // Moon-phase font glyphs, evenly spaced around the cycle: A is new moon
    // (phase 0), I is full moon (phase 0.5).
    private const moonPhaseChars = ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P"];

    function initialize() {
        WatchFace.initialize();
        var settings = Toybox.System.getDeviceSettings();
        screenWidth = settings.screenWidth;
        screenHeight = settings.screenHeight;
        moonFont = WatchUi.loadResource(Rez.Fonts.Moon) as WatchUi.FontResource;
        sunBitmap = WatchUi.loadResource(Rez.Drawables.Sun) as Graphics.BitmapType;
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
        var now = Time.now();
        var unix_timestamp = now.value();

        if(clockTime.sec % 60 == 0 or lastSlowUpdate == null or unix_timestamp - lastSlowUpdate >= 60) {
            lastSlowUpdate = unix_timestamp;
            watch_data.update();
        }
        watch_data.refreshSunPosition();

        adjustPositions();

        var temp = watch_data.Temp;
        if (temp != null and showWeather) {
            var tempData = temp.format("%d") + "ª";
            var windSpeed = watch_data.WindSpeed;
            var windBear = watch_data.WindBear;
            if (windSpeed != null && windBear != null) {
                tempData += windSpeed.format("%d") + getWindChar(windBear) ;
            }
            var rain = watch_data.Rain;
            if (rain != null) {
                tempData += rain.format("%d") + "%";
            }
            writeToLED("Weather",tempData);
        }

        var nextRise = nextMoment(watch_data.Sunrise, watch_data.MoonRise, now);
        var nextSet = nextMoment(watch_data.Sunset, watch_data.MoonSet, now);
        writeToLED("Rise", nextRise != null ? formatTime(nextRise) : "--:--");
        writeToLED("Set", nextSet != null ? formatTime(nextSet) : "--:--");

        var info = ActivityMonitor.getInfo();
        writeToLED("Steps",padNumber(toThousands(info.steps)));
        writeToLED("Floors",padNumber(toThousands(info.floorsClimbed)));

        var notifications = System.getDeviceSettings().notificationCount;
        var notifStr = (notifications > 0) 
            ? toThousands(notifications)
            : "--";
        writeToLED("Notifs",padNumber(notifStr));

        var dt = Gregorian.info(now, Time.FORMAT_LONG);
        var dateStr = Lang.format("$1$ $2$", [dt.day_of_week, dt.day]);
        writeToLED("Date",dateStr.toUpper());

        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);
        drawTicks(dc, 3, 7, 2, Math.PI / 6);
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
        tmpDc.setStroke(handColour);
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

    // Selects the moon-phase glyph (A..P) for watch_data.MoonPhase: the 16
    // glyphs are evenly spaced around the cycle, A at phase 0 (new moon)
    // and I at phase 0.5 (full moon), wrapping back to A at phase 1. The
    // font's image set runs right-to-left through the cycle (mirrored),
    // so the index walks backward from A instead of forward -- A and I
    // land in the same place either way since they're exactly half a
    // (even-sized) cycle apart.
    function getMoonPhaseChar() as String {
        var phase = watch_data.MoonPhase;
        var count = moonPhaseChars.size();
        var idx = Math.round(-phase * count).toNumber() % count;
        if (idx < 0) {
            idx += count;
        }
        return moonPhaseChars[idx];
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

    // Picks whichever of two candidate moments is soonest but still ahead of
    // now (so an already-passed moonrise/moonset from the rough phase-based
    // approximation doesn't win out over an upcoming sunrise/sunset). Falls
    // back to whichever one is in the future if only one is, or null if
    // neither is (missing location data, or both already passed).
    function nextMoment(a as Time.Moment?, b as Time.Moment?, now as Time.Moment) as Time.Moment? {
        var aFuture = (a != null) and now.lessThan(a);
        var bFuture = (b != null) and now.lessThan(b);
        if (aFuture and bFuture) {
            return a.lessThan(b) ? a : b;
        } else if (aFuture) {
            return a;
        } else if (bFuture) {
            return b;
        }
        return null;
    }

    function formatTime(moment as Time.Moment) as String {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return padNumber(info.hour.toString()) + ":" + padNumber(info.min.toString());
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

    // Sky graphics (sun, moon) never render below this y -- the sky-sun.png
    // /sky-night.png art ends in a flat line at this height, so a plain
    // rectangular clip is enough to keep the sun/moon disc from bleeding
    // onto the LED digits below, no per-shape masking needed.
    private const skyClipHeight = 150;

    function drawSky(dc as Dc) as Void {
        var sun_angle = watch_data.SunAngle;
        var moon_angle = watch_data.MoonAngle;
        var is_day = watch_data.IsDay;
        var sky_sun = View.findDrawableById("SkySun") as Bitmap;
        var sky_night = View.findDrawableById("SkyNight") as Bitmap;
        var radius = 173;

        sky_sun.setVisible(is_day);
        sky_night.setVisible(!is_day);

        dc.setClip(0, 0, screenWidth, skyClipHeight);
        if (is_day) {
            drawSun(dc, sun_angle, radius);
        }
        if (moon_angle > 0 and moon_angle < Math.PI) {
            drawMoon(dc, moon_angle, radius);
        }
        dc.clearClip();
    }

    function drawSun(dc as Dc, angle as Float, radius as Number) as Void {
        var half = 45 / 2.0;
        var x = screenWidth / 2 + radius * Math.cos(angle) - half;
        var y = screenHeight / 2 - radius * Math.sin(angle) - half;

        dc.drawBitmap(x.toNumber(), y.toNumber(), sunBitmap);
    }

    // Renders the moon-phase glyph rotated to stay radially aligned with the
    // arc: upright at the zenith (angle = PI/2), tilting toward the horizon
    // on either side, the way the real terminator's apparent orientation
    // shifts as the moon crosses the sky. WatchUi.Text can't be rotated, so
    // this draws the glyph into an offscreen buffer and spins that with an
    // AffineTransform instead, same technique as drawTicks/drawHandBasic.
    // The caller (drawSky) already has the sky clip rect active, so no
    // per-position masking is needed here.
    function drawMoon(dc as Dc, angle as Float, radius as Number) as Void {
        var size = 45;
        var pad = 6;
        var buffer = Graphics.createBufferedBitmap({ :width=>size+pad, :height=>size+pad });
        var tmpDc = buffer.get().getDc();

        tmpDc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        tmpDc.clear();
        tmpDc.setAntiAlias(true);
        tmpDc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        tmpDc.drawText(pad / 2, pad / 2, moonFont, getMoonPhaseChar(), Graphics.TEXT_JUSTIFY_LEFT);

        var theta = Math.PI / 2 - angle;
        var rSin = Math.sin(theta);
        var rCos = Math.cos(theta);
        var pivot = pad / 2 + size / 2.0;

        var transformMatrix = new Graphics.AffineTransform();
        transformMatrix.translate(-pivot * rCos + pivot * rSin, -pivot * rCos - pivot * rSin);
        transformMatrix.rotate(theta);

        var x = screenWidth / 2 + radius * Math.cos(angle);
        var y = screenHeight / 2 - radius * Math.sin(angle);

        dc.drawBitmap2(x, y, buffer, {
            :transform => transformMatrix,
            :filterMode => Graphics.FILTER_MODE_BILINEAR
        });
    }

}
