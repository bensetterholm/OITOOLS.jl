
function mjd_to_utc(mjd)
    """
    This function calculates and returns the UTC given a specific mjd.  It is a julia implementation of the codes  by Peter J. Acklam found
        on http://www.radiativetransfer.org/misc/atmlabdoc/atmlab/time/mjd2date.html and linked pages, except for the error handling (for now)
    """
    jd = mjd + 2400000.5;
    #get year month and days
    intjd = floor(jd+0.5);
    a = intjd+32044;
    b = floor((4 * a + 3) / 146097);
    c = a - floor((b * 146097) / 4);
    d = floor((4 * c + 3) / 1461);
    e = c - floor((1461 * d) / 4);
    m = floor((5 * e + 2) / 153);
    day   = e - floor((153 * m + 2) / 5) + 1;
    month = m + 3 - 12 * floor(m / 10);
    year  = b * 100 + d - 4800 + floor(m / 10);
    #get hour min seconds
    fracmjd = mjd-floor(mjd); #days;
    secs = 86400*fracmjd;
    hour = trunc(secs/3600);
    secs= secs-3600*hour;  #remove hour
    mins = trunc(secs/60); #minutes
    secs = secs -60*mins; #seconds
    return secs,mins,hour,day,month,year
end

function dates_to_jd(dates::Union{Array{Any,2},Array{Float64,2}})
    """
    This function calculates and returns the hour angle for the desired object given a RA, time, and longitude
    of observations.  The program assumes UTC but changing the timezone argument to "local" will adjust the
    input times accordingly.

    Arguments:
    Manual Inputs:
    * date [2018  3 5 21 13 56.7; 2018 3 5 21 14 12.7] day,month,year,hour,min,sec: Correction to UTC is done within code if necessary/dictated.
    * longitude: degree (in decimal form) value of the longitudinal location of the telescope.
    * ra: [h,m,s] array of the right ascension of the desired object.

    Optional Inputs:
    * dst: ["yes","no"] whether daylight savings time needs to be accounted for.
    * ldir: ["W","E"] defines the positive direction for change in longitude (should be kept to W for best applicability).
    * timezone: ["UTC","local"] states whether the time inputs are UTC or not.  If not the code will adjust the times as needed with the given longitude.

    Accuracy:
    * With preliminary testing the LST returned is accurate to within a few minutes when compared with other calculators (MORE TESTING AND QUANTITATIVE ERROR NEEDS TO BE ESTABLISHED).
    """
    if ldir == "W"
        alpha = -1.
    elseif ldir == "E"
        alpha = 1.
    end
    years=Int.(dates[:,1])
    months=Int.(dates[:,2])
    days = Int.(dates[:,3])
    hours=Int.(dates[:,4])
    minutes=Int.(dates[:,5])
    seconds=Float64.(dates[:,6])
    h_ad = alpha*longitude/15 #Measures the hours offset due to longitude
    if timezone != "UTC"
        if dst=="no"
            hours .-= h_ad
        elseif dst=="yes"
            h_ad += 1
            hours .-= h_ad
        end
        wrap_hours_over = findall(hours.>24)
        hours[wrap_hours_over] .-= 24
        days[wrap_hours_over] .+= 1

        wrap_hours_under = findall(hours.<0)
        hours[wrap_hours_under] +=24
        days[wrap_hours_under] -= 1
    end

    #Below: the code calculates first the Julian Date given the input time and then determines the GMST based
    #on this JD.  This is then converted to LST and finally to Local Hour Angle (LHA or HA).  The final result
    #is in terms of hours for both LST and HA.
    jdn = floor.((1461*(years .+4800 .+(months.-14)/12))/4+(367*(months .-2-12*((months.-14)/12)))/12-(3*((years .+4900 +(months.-14)/12)/100))/4 .+days.-32075)
    jdn = jdn + ((hours.-12)/24)+(minutes/1440)+(seconds/86400)
    jd0 = jdn .-2451545.0
    return jd0
end


function jd_to_hour_angle(jd:Array{Float64,1},tel_longitude::Float64, obj_ra::Float64;dst="no",ldir="W",timezone="UTC")

"""
This function calculates and returns the hour angle for the desired object given the object RA, the JD time, and longitude
of observations.
Arguments:
Manual Inputs:
* longitude: degree (in decimal form) value of the longitudinal location of the telescope.
* ra: [h,m,s] array of the right ascension of the desired object.
Accuracy:
* With preliminary testing the LST returned is accurate to within a few minutes when compared with other calculators (MORE TESTING AND QUANTITATIVE ERROR NEEDS TO BE ESTABLISHED).
"""

t = jd/36525.0 # TODO check that correct jd here (= rjd - 51545.0) ???
# Greenwich Mean Sidereal Time at Oh UT (in seconds)
H = 24110.54841 .+ 8640184.812866*t + 0.093104*t.^2 - 6.2e-6*t.^3
w = 1.00273790935 .+ 5.9e-11*t  # what's this ???
tt = hours*3600 + minutes*60 + seconds # what's this ???
gmst = H + w.*tt #seconds
# Greenwich Mean Sidereal Time in hours
gmst = gmst/3600 #hours
gmst_over = findall(gmst.>24)
gmst[gmst_over] -= (24*floor.(gmst[gmst_over]/24))
# Local Mean Sidereal Time in hours at 0h UT (longitude correction)
lst = gmst .+ longitude/15
lst_under = findall(lst.<0)
lst_over = findall(lst.>24)
lst[lst_under] .+= 24
lst[lst_over] -= (24*floor.(lst[lst_over]/24))
# HA of star at 0h UT on RJD
hour_angle = lst .-ra
return lst, hour_angle
end


function opd_limits(base, alt, az)
    s = hcat(cos.(alt).*cos.(az),cos.(alt).*sin.(az),sin.(alt))'
    opd = dot(base,s) #in meters (?)
    return opd
end

function alt_az(dec_deg,lat_deg, ha_hours) #returns alt, az in degrees
    dec = dec_deg*pi/180;
    ha = ha_hours*pi/12
    lat = lat_deg*pi/180
    # Simple version
    alt = asin.(sin(dec)*sin(lat).+cos(dec)*cos(lat)*cos.(ha))
    az = atan.((-cos(dec)*sin.(ha))./(sin(dec)*cos(lat).-cos(dec)*cos.(ha)*sin(lat)))
    return alt*180/pi, az*180/pi
end

function geometric_delay(l,h,δ,baselines)
    Δgeo = - (sin(l)*cos(δ)*cos.(h).-cos(l)*sin(δ) ).*baselines[1,:] -(cos(δ)*sin.(h)) .* baselines[2,:] + (cos(l)*cos(δ)*cos.(h)).*baselines[3,:]
    return
end

function cart_delay(baselines)
    Δcarts = -0.5*(geometric_delay(l,h,δ,baselines) - airpath_delay(baselines) + pop_delay(baselines))
    return Δcarts
end



# Example AZ Cyg

# AZ Cyg
dec = [46, 28, 0.573182]'*[1.0, 1/60., 1/3600];

#CHARA
lat = 34.2243836944;
alt_limit = 25; # observe above 25 degrees elevation

# Full HA
ha = collect(range(-12, 12, step=1.0/60))

# print transit time (ha = 0)
alt, az = alt_az(dec, lat, ha) # result will be in degrees
good_alt = findall(alt.>alt_limit)
ha_good_alt = ha[good_alt[1]:good_alt[end]]
print("HA range based on CHARA telescope elevation limit: from ", ha[good_alt[1]], " to ",  ha[good_alt[end]] )


h = hour_angles * pi / 12; #✓
δ =  /180*pi #✓
l = facility.lat[1]/180*pi; #✓

ntel=facility.ntel[1] #✓
    nhours = length(hour_angles); #✓
    h = hour_angles' .* pi / 12; #✓
    δ=observatory.decep0[1]/180*pi #✓
    l=facility.lat[1]/180*pi; #✓
    λ=wave_info_out.lam#✓
    δλ=wave_info_out.del_lam #✓
    nw=length(λ)

    station_xyz=Array{Float64}(undef,ntel,3) #✓
    staxyz=Array{Float64}(undef,3,ntel); #✓
    for i=1:ntel[1] #✓
        station_xyz[i,1:3]=facility.sta_xyz[(i*3-2):i*3]#✓
    end

    for i=1:ntel #✓
            staxyz[:,i]=station_xyz[i,:];#✓
    end

    nv2,v2_baselines,v2_stations,v2_stations_nonredun,v2_indx,baseline_list,ind=get_v2_baselines(ntel,station_xyz,facility.tel_names);

    nt3,t3_baselines,t3_stations,t3_indx_1,t3_indx_2,t3_indx_3,ind=get_t3_baselines(ntel,station_xyz,v2_stations);

    nuv, uv, u_M, v_M, w_M=get_uv(l,h,λ,δ,v2_baselines)