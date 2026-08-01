import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

// Holds the weather/sun data used to drive the watch face, and knows how
// to refresh itself from the device's weather and location APIs.
class WatchData {
    public var Temp as Number?;
    public var WindBear as Number?;
    public var WindSpeed as Number?;
    public var Rain as Number?;
    public var Night as Boolean = false;
    public var Sunrise as Time.Moment?;
    public var Sunset as Time.Moment?;
    public var MoonRise as Time.Moment?;
    public var MoonSet as Time.Moment?;
    public var Location as Position.Location?;

    // Angle of the sun in the sky: 8*PI/9 at sunrise (upper left), PI/2 at
    // solar noon (top), PI/9 at sunset (upper right) -- standard polar
    // angle, sweeping left to right across the day.
    public var SunAngle as Float = Math.PI;

    // Approximates the moon's position by offsetting the sun's arc by the
    // current lunar phase: at a new moon the offset is 0 (moon tracks the
    // sun), at a full moon it's PI (moon is opposite the sun, i.e. it's up
    // when the sun is down), etc. This avoids needing a full lunar
    // ephemeris, at the cost of accuracy. The moon LAGS the sun as the
    // phase advances (that's why moonrise gets ~50min later each day), so
    // this is a subtraction, not an addition.
    public var MoonAngle as Float = Math.PI;

    // Fraction of the way through the current lunar cycle, 0..1 (0 = new moon).
    public var MoonPhase as Float = 0.0;

    // Whether it's currently daytime, from a direct now-vs-sunrise/sunset
    // comparison (see getSunRawAngle) rather than inferred from SunAngle's
    // wrapped range. Refreshed every frame by refreshSunPosition().
    public var IsDay as Boolean = true;

    function initialize() {
    }

    function update() as Void {
        var cc = Weather.getCurrentConditions();
        if (cc != null) {
            var loc = cc.observationLocationPosition;
            var now = Time.now();
            Temp = cc.temperature as Number;
            WindBear = cc.windBearing as Number;
            WindSpeed = cc.windSpeed as Number;
            Rain = cc.precipitationChance as Number;
            Night = false;
            if (loc != null) {
                Location = loc;
                var sunrise = Weather.getSunrise(loc, now);
                var sunset = Weather.getSunset(loc, now);
                if (sunrise.lessThan(now)) {
                    //if sunrise was already, take tomorrows
                    sunrise = Weather.getSunrise(loc, Time.today().add(new Time.Duration(86401)));
                } else {
                    Night = true;
                }
                if (sunset.lessThan(now)) {
                    //if sunset was already, take tomorrows
                    Night = true;
                    sunset = Weather.getSunset(loc, Time.today().add(new Time.Duration(86401)));
                }
                Sunrise = sunrise;
                Sunset = sunset;
                updateMoonRiseSet(loc, now);
            } else {
                Sunrise = null;
                Sunset = null;
                MoonRise = null;
                MoonSet = null;
            }
        }
    }

    // Approximate moonrise/moonset for the current day/night cycle, derived
    // from the same sun-arc-plus-phase-offset model as MoonAngle: moonrise
    // is the moment the sun's raw angle reaches MoonPhase*2*PI (the moon
    // rises MoonPhase of a full cycle after the sun does), and moonset is
    // PI further along from there.
    private function updateMoonRiseSet(loc as Position.Location, now as Time.Moment) as Void {
        var today = Time.today();
        var sunrise = Weather.getSunrise(loc, today);
        var sunset = Weather.getSunset(loc, today);
        if (sunrise == null || sunset == null) {
            MoonRise = null;
            MoonSet = null;
            return;
        }

        var nightStart, nightEnd;
        if (now.lessThan(sunrise)) {
            nightStart = Weather.getSunset(loc, today.subtract(new Time.Duration(86400)));
            nightEnd = sunrise;
        } else {
            nightStart = sunset;
            nightEnd = Weather.getSunrise(loc, today.add(new Time.Duration(86400)));
        }
        if (nightStart == null || nightEnd == null) {
            MoonRise = null;
            MoonSet = null;
            return;
        }

        // Pinned to "today" rather than "now": using a live phase here would
        // make the computed rise/set targets creep forward on every refresh
        // as the phase keeps advancing, even within the same night.
        var phase = computeMoonPhase(today);
        var riseTarget = wrapRaw(phase * 2 * Math.PI);
        var setTarget = wrapRaw(Math.PI + phase * 2 * Math.PI);

        MoonRise = rawToTime(riseTarget, sunrise, sunset, nightStart, nightEnd);
        MoonSet = rawToTime(setTarget, sunrise, sunset, nightStart, nightEnd);
    }

    private function wrapRaw(raw as Float) as Float {
        while (raw >= 2 * Math.PI) { raw -= 2 * Math.PI; }
        while (raw < 0) { raw += 2 * Math.PI; }
        return raw;
    }

    // Inverse of the day/night raw-angle mapping used by getSunRawAngle:
    // given a target raw value (0..2*PI, 0 = rise, PI = set), finds the
    // moment within the day segment [dayStart,dayEnd] or the adjacent night
    // segment [nightStart,nightEnd] where the raw angle equals that target.
    private function rawToTime(raw as Float, dayStart as Time.Moment, dayEnd as Time.Moment, nightStart as Time.Moment, nightEnd as Time.Moment) as Time.Moment {
        if (raw <= Math.PI) {
            var frac = raw / Math.PI;
            return dayStart.add(new Time.Duration((frac * (dayEnd.value() - dayStart.value())).toNumber()));
        } else {
            var frac = (raw - Math.PI) / Math.PI;
            return nightStart.add(new Time.Duration((frac * (nightEnd.value() - nightStart.value())).toNumber()));
        }
    }

    // Recomputes SunAngle/MoonAngle/MoonPhase for the current moment. Unlike
    // update(), this doesn't touch the weather/location APIs -- it's just
    // trig on top of Location, so it's cheap enough to call every frame for
    // a smoothly moving sun/moon.
    function refreshSunPosition() as Void {
        var raw = getSunRawAngle();
        SunAngle = toSkyAngle(raw);

        MoonPhase = computeMoonPhase(Time.now());
        MoonAngle = toSkyAngle(raw - MoonPhase * 2 * Math.PI);
    }

    // Raw angle in 0..2*PI, with 0 = sunrise, PI = sunset. Also refreshes
    // IsDay from the same sunrise/sunset comparison, since it's the direct
    // source of truth for day/night (as opposed to inferring it from
    // SunAngle's wrapped range).
    private function getSunRawAngle() as Float {
        var loc = Location;
        if (loc == null) {
            IsDay = true;
            return Math.PI;
        }

        var now = Time.now();
        var today = Time.today();
        var sunrise = Weather.getSunrise(loc, today);
        var sunset = Weather.getSunset(loc, today);
        if (sunrise == null || sunset == null) {
            IsDay = true;
            return Math.PI;
        }

        if (now.lessThan(sunrise)) {
            IsDay = false;
            var prevSunset = Weather.getSunset(loc, today.subtract(new Time.Duration(86400)));
            return (prevSunset == null) ? Math.PI : arcAngle(now, prevSunset, sunrise, Math.PI, 2 * Math.PI);
        } else if (now.lessThan(sunset)) {
            IsDay = true;
            return arcAngle(now, sunrise, sunset, 0.0, Math.PI);
        } else {
            IsDay = false;
            var nextSunrise = Weather.getSunrise(loc, today.add(new Time.Duration(86400)));
            return (nextSunrise == null) ? Math.PI : arcAngle(now, sunset, nextSunrise, Math.PI, 2 * Math.PI);
        }
    }

    // Fraction of the way through the lunar cycle at the given moment, 0..1
    // (0 = new moon).
    private function computeMoonPhase(at as Time.Moment) as Float {
        var knownNewMoon = Gregorian.moment({:year=>2000, :month=>1, :day=>6, :hour=>18, :minute=>14});
        var synodicMonthSeconds = 29.530588853 * 86400;
        var elapsed = at.subtract(knownNewMoon).value().toFloat();
        var cycles = elapsed / synodicMonthSeconds;
        return cycles - Math.floor(cycles);
    }

    // Linear interpolation of `now` between `start` and `end`, mapped from
    // startAngle to endAngle.
    private function arcAngle(now as Time.Moment, start as Time.Moment, end as Time.Moment, startAngle as Float, endAngle as Float) as Float {
        var frac = (now.value() - start.value()).toFloat() / (end.value() - start.value());
        return startAngle + frac * (endAngle - startAngle);
    }

    // Converts a raw 0..2*PI angle (0 = rise, PI = set) to a standard polar
    // angle, with rise/set remapped from PI/0 to 5*PI/6 / PI/6 (i.e. the sun
    // and moon stay within the upper part of the circle instead of touching
    // the horizontal edges), wrapped to (-PI..PI].
    private function toSkyAngle(raw as Float) as Float {
        while (raw >= 2 * Math.PI) { raw -= 2 * Math.PI; }
        while (raw < 0) { raw += 2 * Math.PI; }

        var riseAngle = 8 * Math.PI / 9;
        var setAngle = Math.PI / 9;

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
}
