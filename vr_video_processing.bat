@echo off
setlocal ENABLEDELAYEDEXPANSION
set fp=10000

::
::  file: vr_video_processing.bat
::
::  Author: Aruã Metello - contact: aruametello@gmail.com
::
::  Descripton: 
::  uses ffmpeg, avisynth, mvtools2 and ffms2 to deshake
::  and downsample the framerate to a proper paced 60 frames per second
::  
::  it is intended to use with VR gameplay footage, but works with
::  any videos you feed it. (shaky cams at uneven framerates)
::
:: -------------------------------------
:: if you are looking to tweak extra stuff, maybe those are the settings you are looking for

:: lowballing the zoom will cause a black border to apear when the screen shakes
:: bigger zoom = better avoidance of black borders but the video is more cropped
:: values: 0 - 100 (percent)
set zoom=17

:: smooth camera factor is somewhat how inertial the camera movement is (measure in buffer frames before and after the shake)
:: values: 0 - infinite (its proportional to your input framerate, 30 is probably a lot)
set smooth_camera_factor=12

:: shakiness regulates how fast the camera respond to motion. (low values means it will lag behind laggier)
:: values: 0 - 10
set shakiness_camera_factor=9


:: video quality compression, 18 = very high and huge file, 28 = moddest size
:: avoid a value too low if you intent to edit the video later
:: you really dont want this bellow 18... ?
set output_video_quality_ratefactor=19



::
:: there are way more complex stuff in if you are interesting in dealing with the 
:: avisynth scripting step, perhalps creating a less blurry "motion blur" ?
::
:: check the gen_avisynth_script function to see what is going on there
::
:: what this script does is to upsample whatever framerate input we have into 960fps
:: and then merge the frames that are correctly aligned within each 16.7ms window of
:: the 60fps output. 
::
:: it fixes the uneven motion in the displayed frames recorded above 60fps.
::
:: This can create good results with just 72hz gameplay (like i did), but the more
:: frames the better, multiples of 60 are ideal (120hz?) but make sure you can run
:: the game without dropping from the target framerate! unstable 120hz is worse than stable 80hz

:: -------------------------------------
rem fancy colors to make readability somewhat better.
rem modified, original from here https://gist.github.com/mlocati/fdabcaeb8071d5c75a2d51712db24011#file-win10colors-cmd

set cDEFAULT=[0m
set cUnderline=[4m

set cRED=[31m
set cGREEN=[32m
set cYELLOW=[33m
set cCYAN=[36m
set cWHITE=[90m


set sGRAY=[90m

set sRED=[91m
set sGREEN=[92m
set sYELLOW=[93m
set sBLUE=[94m
set sMAGENTA=[95m
set sCYAN=[96m
set sWHITE=[97m


set cUP1LINE=[1A
set fBOLD=[1A
set cCOLUMN=[40G


:start_over
set cdir=%cd%
set script_dir=%~dp0
cd /d !script_dir!

Title ### vr video motion smoother thingy ###
cls
echo %cCYAN%checking dependencies... 





rem starting state of the terminal colors
echo %cDEFAULT%


rem create the local temporary folder if needed
mkdir temporary_files >NUL 2>NUL


rem transforms path cant have quotes?
set transforms_temp=motion_data_%random%.trf
set mkv_temp="temporary_files\vr_video_processing_temp_%random%%random%%random%%random%.mkv"
set avs_temp="temporary_files\avisynth_%random%%random%%random%%random%.avs"


set url_ffmpeg=https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z
set url_avisynth=https://github.com/AviSynth/AviSynthPlus/releases/download/v3.7.0/AviSynthPlus_3.7.0_20210111.exe


set ffmpeg_prepend=-y -loglevel error -stats
set ffmpeg_decoder_opts=-c:v h264_cuvid
set ffmpeg_encoder_opts=-c:v h264_nvenc

set show_cmdline=1




rem queriyng from the registry where avisynth is installed
set AVISYNTH_FOLDER=none
FOR /F "tokens=2* delims= " %%a IN ('REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\AviSynth" /v plugindir2_5 2^>NUL') do set AVISYNTH_FOLDER=%%b


call :test_thing "FFMPEG.exe available" "bin\ffmpeg -version" " * bin\ffmpeg.exe seems to be missing, download the zip at %url_ffmpeg% and copy the file bin\ffmpeg.exe to the bin folder of this script. %cd%"
if !error_test_thing!==1 call :fatal_error_pause


call :test_thing "FFPROBE.exe available" "bin\ffprobe -version" " * bin\ffprobe.exe seems to be missing, download the zip at %url_ffmpeg% and copy the file bin\ffprobe.exe to the bin folder of this script. %cd%"
if !error_test_thing!==1 call :fatal_error_pause


call :test_thing "Avisynth+ is installed" "REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\AviSynth" /v plugindir2_5" " * You seem to be missing Avisynth+!"
if !error_test_thing!==1 (
	if "%AVISYNTH_FOLDER%"=="none" (
		echo. 
		echo avisynth+ is required and does not seem to be installed yet.
		echo.
		echo i can install it for you from the file avisynth_installer\AviSynthPlus_3.7.0_20210111.exe
		echo.
		choice /C YN /M "Proceed with the install?"
		if "%ERRORLEVEL%"=="1" (
		
			if EXIST avisynth_installer\AviSynthPlus_3.7.0_20210111.exe (
				start /wait avisynth_installer\AviSynthPlus_3.7.0_20210111.exe /silent
				goto start_over
			)else (
				echo Missing avisynth_installer\AviSynthPlus_3.7.0_20210111.exe
				call :fatal_error_pause				
			)
		)else (
			call :fatal_error_pause
		)
	)
	rem wtf?
	call :fatal_error_pause
)

call :gen_avisynth_test
call :test_thing "FFMPEG supports Avisynth scripts" "bin\ffmpeg -y -i %avs_temp% -t 0.1 -f null -" " * Avisynth is not working with ffmpeg, download it at !url_avisynth! or your FFMPEG current executable was compiled without avisynth support."
if !error_test_thing!==1 call :fatal_error_pause


call :gen_avisynth_plugin_test
call :test_thing "Avisynth required plugins" "bin\ffmpeg -y -i %avs_temp% -t 0.1 -f null -" " * You might be missing the ffms2.dll and/or mvtools2.dll plugins in the avisynth_plugins folder."
if !error_test_thing!==1 (
call :fatal_error_pause
)


call :test_thing_optional "FFMPEG can use Nvidia h264 encoding" "bin\ffmpeg -y -i %avs_temp% -c:v h264_nvenc -t 2.0 !mkv_temp!" " * Not required. This is only available on nvidia GPUs and can speedup the process."
if !error_test_thing!==1 (
rem use software encoding
set ffmpeg_encoder_opts=-c:v libx264
rem use software decoding
set ffmpeg_decoder_opts=
)else (

 rem delete the temporary mkv
 del !mkv_temp! >NUL 2>NUL 
 
 rem delete the test script 
 del !avs_temp! >NUL 2>NUL

)






rem call :test_thing "FFMPEG can use Nvidia h264 decoding" "bin\ffmpeg -y -c:v h264_cuvid -i ^"!mkv_temp!^" -c:v h264_nvenc -f null -" "Not required. This is only available on geforce GPUs and can speed up the process."
rem if !error_test_thing!==1 (
rem set ffmpeg_decoder_opts=
rem set nvidia_decoder=0
rem )










rem maybe the user will drag+drop the file onto the script file instead of the window?
if NOT "%~1"=="" (
	set input_motion="%~1"
	echo %cDEFAULT%
	echo Using "%~1" as the input file from the command line.
)else (
	:ask_input_again
	rem Pergunta pro usuario as opcoes a utilizar
	echo %cDEFAULT%
	echo # Type or drag and drop the input video file on this window to fill this field.
	set input_motion=
	set /P input_motion=%sWHITE%Input file name:%cDEFAULT%
	
	if "!input_motion!"=="" (
		echo %sRED%error:%sYellow% the input_motion field can not be blank.%cdefault%
		goto ask_input_again
	)else (	
		if NOT EXIST "!input_motion!" (
			echo %sRED%error:%sYellow% cant read !input_motion!, check if the path is correct.%cdefault%
			goto ask_input_again		
		)
	)	
)



rem temporary file for the deshaken but still not interpolated motion
set mkv_temp=%cd%\pre_interp_deshaken_video_%random%.mkv



rem check the source file

set input_has_audio=0
set input_has_video=0
set final_input_mapping=-i !avs_temp!


for /f "tokens=1* delims==" %%a in ('bin\ffprobe -v quiet -i !input_motion! -print_format ini -show_streams ^2^>^&1') do (
	rem echo %%a -- %%b
	if "%%a"=="codec_name" set ffprobe_codec_name=%%b
	if "%%a"=="codec_type" set ffprobe_codec_type=%%b
	if "%%a"=="width" set ffprobe_width=%%b
	if "%%a"=="height" set ffprobe_height=%%b
	if "%%a"=="codec_name" set ffprobe_codec_name=%%b

	if "%%a"=="r_frame_rate" for /f "tokens=1,2 delims=/" %%c in ("%%b") do (

		rem echo framerate: %%c e %%d
	
		if "%%d"=="" (
			set /a ffprobe_r_frame_rate_100=^(%%c * !fp!^)
		)else (
			if "%%d"=="0" (
				rem nao executar uma divisao por zero!
				set /a ffprobe_r_frame_rate_100=^(%%c * !fp!^)
			)else (
				set /a ffprobe_r_frame_rate_100=^(%%c * !fp!^) / %%d
			)
		)
	)


	if "%%a"=="duration" (
		set ffprobe_duration=%%b
		
		if "!ffprobe_codec_type!"=="audio" (
			set input_has_audio=1
			rem put the original untouched audio into the final file.
		)
		
		if "!ffprobe_codec_type!"=="video" (
			set input_has_video=1
			call :format_float !ffprobe_r_frame_rate_100!
			echo %cCYAN%Input video format: %sYELLOW%!ffprobe_codec_name! !ffprobe_width!x!ffprobe_height!@!ret_float!fps%cDEFAULT%
			
			rem warn if the captured framerate suck
			if /i !ffprobe_r_frame_rate_100! LSS 60000 echo %sRED%Warning:%cYELLOW% this video file does not seem to be a full framerate capture, OBS using "game capture" + match video fps to VR screen frequency is strongly recomended!. if not the result might suck.%cDEFAULT%
			
			rem warn if the video aspect ratio suck
			set /a aspect_ratio_100= ^(!ffprobe_width! * 100^) / !ffprobe_height!
			if /i !aspect_ratio_100! GTR 145 echo %sRED%Warning: %cYELLOW%the aspect ratio of the video seems too wide, the end result will likely be VERY zoomed in after deshaking!%cDEFAULT%
						
			rem warn if the input video stream format suck
			if NOT "!ffprobe_codec_name!"=="h264" (
				echo %sRED%Warning: %cYELLOW%the input video stream is not h264, decoding the input might be slower and wont use nvidia hardware acceleration.%cDEFAULT%
				set ffmpeg_decoder_opts=				
				set nvidia_decoder=0				
			)		
		)
	)
)


rem warn the user if the file is weird
if "!input_has_video!"=="0" echo %sRED%ERROR: input file has no video stream.%cDEFAULT% & call :fatal_error_pause
if "!input_has_audio!"=="0" echo %sRED%NOTICE: input file has no audio stream.%cDEFAULT%




rem read some filename for the output
echo.
echo # Type the name of the output file (without extension) or leave blank to generate automatically a filename.
set /P output_motion=%sWHITE%Output file name:%cDEFAULT%


rem empty field = random file name
if "%output_motion%"=="" (
set output_motion=!cdir!\interp_%random%.mp4
)else (
set output_motion=!cdir!\!output_motion!.mp4
)



rem ---------------------------------------------------
:ask_time
echo.
echo # Input the start of the cut in the hh:mm:ss format or leave blank to use the whole video.
echo hh:mm:ss format like 01:10:12
set /p ts_start=%sWHITE%Start timestamp:%cDEFAULT%

if NOT "!ts_start!"=="" (

  for /f tokens^=1^,2^,3^ delims^=: %%a in ('echo !ts_start!') do (  
	call :trim_zeroes %%a
	set r_a=!num_ret!
	call :trim_zeroes %%b
	set r_b=!num_ret!
	call :trim_zeroes %%c
	set r_c=!num_ret!

	if "!r_c!"=="" (	
	if "!r_b!"=="" (	
	 set ts_start_secs=!r_a!
	) else (	  
	 set /a ts_start_secs=^( !r_a! * 60 ^) + !r_b!
	)	
	)else ( 
	 set /a ts_start_secs=^( !r_a! * 3600 ^) + ^( !r_b! * 60 ^) + !r_c!
	)   
  )
)



if NOT "!ts_start!"=="" (
	:ask_time_end
	echo.
	echo # Input the end of the cut in the hh:mm:ss format
	set /p ts_end=%sWHITE%End timestamp:%cDEFAULT%
	if NOT "!ts_end!"=="" (
	 
	  for /f tokens^=1^,2^,3^ delims^=: %%a in ('echo !ts_end!') do (  
		call :trim_zeroes %%a
		set r_a=!num_ret!
		call :trim_zeroes %%b
		set r_b=!num_ret!
		call :trim_zeroes %%c
		set r_c=!num_ret!


		if "!r_c!"=="" (	
		if "!r_b!"=="" (	
		 set ts_end_secs=!r_a!
		) else (	  
		 set /a ts_end_secs=^( !r_a! * 60 ^) + !r_b!
		)	
		)else ( 
		 set /a ts_end_secs=^( !r_a! * 3600 ^) + ^( !r_b! * 60 ^) + !r_c!
		)   
	  )
	  
	  rem echo set /a duration_user=!ts_end_secs! - !ts_start_secs!
	  set /a duration_user=!ts_end_secs! - !ts_start_secs!

	  if !duration_user! LSS 0 (
	  echo.
	  echo %sRED%ERROR:%sYellow% Check the timestamps, they seem invalid!
	  echo.
	  goto ask_time_end
	  )
	)
)


if NOT "!ts_start_secs!"=="" set ts_start_secs=-ss !ts_start_secs!
if NOT "!duration_user!"=="" set duration_user=-t !duration_user!

rem ---------------------------------------------------



:: motion blur strength
echo.
echo # Motion Blur setting, use your number keys (1 to 4) to choose.
echo.
echo %cGREEN%(1) Maximum %cCYAN%^(equivalent to a real camera with 16.7ms exposure^)%cDEFAULT%
echo %cGREEN%(2) High    %cCYAN%^(Avoids exessive blur, still smooth^)%cDEFAULT%
echo %cGREEN%(3) Average %cCYAN%^(retains most of the focus on motion^)%cDEFAULT%
echo %cGREEN%(4) Minimum %cCYAN%^(can cause motion artifacts^)%cDEFAULT%
echo %sWHITE%
choice /C 1234 /M "Motion blur setting:"
goto config_mblur_%ERRORLEVEL%
:config_mblur_1
set frame_blending_mixing_weigth_f1=0.5
set frame_blending_mixing_weigth_f2=0.5
set frame_blending_mixing_weigth_f3=0.5
set frame_blending_mixing_weigth_f4=0.5
goto mblur_end
:config_mblur_2
set frame_blending_mixing_weigth_f1=0.5
set frame_blending_mixing_weigth_f2=0.625
set frame_blending_mixing_weigth_f3=0.750
set frame_blending_mixing_weigth_f4=0.875
goto mblur_end
:config_mblur_3
set frame_blending_mixing_weigth_f1=0.650
set frame_blending_mixing_weigth_f2=0.737
set frame_blending_mixing_weigth_f3=0.824
set frame_blending_mixing_weigth_f4=0.911
goto mblur_end
:config_mblur_4
set frame_blending_mixing_weigth_f1=0.8
set frame_blending_mixing_weigth_f2=0.85
set frame_blending_mixing_weigth_f3=0.90
set frame_blending_mixing_weigth_f4=0.95
:mblur_end
:: f1 to f4 means how each frame (newest to oldest) will be blended in weigth (merge function in avisynth)
:: maximum does blend all frames in a 16.7 window with equal weigths (think long exposure)
:: the other options deemphasize the older frames, making them more transparent. (how some games do motion blur)




rem ---------------------------------------------------
goto skip_duplicate_question
echo %cdefault%
echo # Duplicate frames
echo.
echo Dropping duplicate frames can improve motion smoothness if your gameplay video couldnt hit flawless performance,
echo but may cause a video desync if too many frames are dropped in an uneven rate.
echo %sWHITE%

set mp_decimate_filter=
choice /C YN /M "Drop duplicate frames?"
if "%ERRORLEVEL%"=="1" set mp_decimate_filter=mpdecimate=hi=3036:lo=640:frac=1.0,setpts=N/FRAME_RATE/TB,

:skip_duplicate_question


rem ---------------------------------------------------
echo %cdefault%
echo # Aspect ratio
echo.
echo %cGREEN%(1) 4:3    %cCYAN%^(recomended: a good balance between field of view and shape^)%cDEFAULT%
echo %cGREEN%(2) 16:9   %cCYAN%^(cuts out vertical detail, but fills regular tv/monitors^)%cDEFAULT%
echo %cGREEN%(3) 1:1    %cCYAN%^(a square image, natural to eye but weird in a screeen^)%cDEFAULT%
echo %cGREEN%(4) Original %cCYAN%^(use aspect and resolution as is^)%cDEFAULT%
echo %sWHITE%
choice /C 1234 /M "Aspect ratio:"
set ret=%ERRORLEVEL%
if "!ret!"=="1" set aspect_ratio=4:3
if "!ret!"=="2" set aspect_ratio=16:9
if "!ret!"=="3" set aspect_ratio=1:1
if "!ret!"=="4" set aspect_ratio=original & set output_x=!ffprobe_width! & set output_y=!ffprobe_height!


rem ---------------------------------------------------

if "!aspect_ratio!"=="16:9" (
echo %cdefault%
echo # Output resolution
echo.
echo %cGREEN%^(1^) 1920x1080  %cCYAN%^(a regular youtube video^)%cDEFAULT%
echo %cGREEN%^(2^) 1600x900   %cCYAN%^(average^)%cDEFAULT%
echo %cGREEN%^(3^) 1280x720   %cCYAN%^(might be enough for discord, can save time^)%cDEFAULT%
echo %sWHITE%
choice /C 123 /M "Resolution setting:"
set ret=%ERRORLEVEL%
if "!ret!"=="1" set output_x=1920& set output_y=1080
if "!ret!"=="2" set output_x=1600& set output_y=900
if "!ret!"=="3" set output_x=1280& set output_y=720
)

if "!aspect_ratio!"=="4:3" (
echo %cdefault%
echo # Output resolution
echo.
echo %cGREEN%^(1^) 1440x1080 %cCYAN%^(youtube 1080p with 4:3 display^)%cDEFAULT%
echo %cGREEN%^(2^) 1200x900  %cCYAN%^(average^)%cDEFAULT%
echo %cGREEN%^(3^) 960x720   %cCYAN%^(just above a dvd^)%cDEFAULT%
echo %sWHITE%
choice /C 123 /M "Resolution setting:"
set ret=%ERRORLEVEL%
if "!ret!"=="1" set output_x=1440& set output_y=1080
if "!ret!"=="2" set output_x=1200& set output_y=900
if "!ret!"=="3" set output_x=960& set output_y=720
)

if "!aspect_ratio!"=="1:1" (
echo %cdefault%
echo # Output resolution
echo.
echo %cGREEN%^(1^) 1440x1440 %cCYAN%^(high res, good for editing^)%cDEFAULT%
echo %cGREEN%^(2^) 1080x1080 %cCYAN%^(sort of 1080p^)%cDEFAULT%
echo %cGREEN%^(3^) 900x900   %cCYAN%^(low res^)%cDEFAULT%
echo %sWHITE%
choice /C 123 /M "Resolution setting:"
set ret=%ERRORLEVEL%
if "!ret!"=="1" set output_x=1440& set output_y=1440
if "!ret!"=="2" set output_x=1080& set output_y=1080
if "!ret!"=="3" set output_x=900& set output_y=900
)




rem ---------------------------------------------------
:: target framerate output
echo.
echo # Target output framerate.
echo.
echo %cGREEN%(1) 60FPS%cDEFAULT%
echo %cGREEN%(2) 30FPS%cDEFAULT%
echo.
choice /C 12 /M "Output framerate:"
goto config_fps_%ERRORLEVEL%
:config_fps_1
set target_fps=60
set output_30_fps=0
goto config_fps_end
:config_fps_2
set target_fps=30
set output_30_fps=1
goto config_fps_end
:config_fps_end



rem ------------------------------
rem calculations related to cropping and aspect ratio


set input_x=!ffprobe_width!
set input_y=!ffprobe_height!


rem screen ratio of the input and output
set /a scale_in=(input_x*!fp!) / input_y
set /a scale_out=(output_x*!fp!) / output_y




rem ================
rem nescessario mudar a razao do video?
if NOT "!scale_in:~0,3!"=="!scale_out:~0,3!" (
 rem compare if they are "close enough", because this batch file floating point
 rem match is an unholy mess of low accuracy

 set /a crop_scale_y = !scale_out! * !fp! / !scale_in!
 
 if !crop_scale_y! LSS !fp! (
   echo %sRED%ERROR:%sYellow% the input footage is less "tall" than the !aspect_ratio! requested aspect ratio.
   echo        its not possible to crop this video without ruining the horizontal FOV.
   echo        try with a wider aspect ratio or recapture the video using the full frame of STEAMVR.%cdefault%
   call :fatal_error_pause 
 )
 
 call :format_float !crop_scale_y!
 set crop_x=1.0
 set crop_y=!ret_float!

 rem echo crop_Y=!crop_y!

 rem se a razao de entrada bate, n precisa do crop
 set crop_filter=,crop=in_w/!crop_x!:in_h/!crop_y!:^(in_w-^(in_w/!crop_x!^)^)/2:^(in_h-^(in_h/!crop_y!^)^)/2
)else (
 rem no need for crop filter
 set crop_filter=
)

rem ================
rem nescessario mudar a resolucao do video?
if NOT "!output_x!x!output_y!"=="!input_x!x!input_y!" (
 rem se a resolucao de entrada bate, nao precisa do resize
 set resize_filter=,scale=!output_x!:!output_y!
)else (
 set resize_filter=
)


rem echo BLUR: !frame_blending_mixing_weigth_f4!
rem echo !input_x!x!input_y! to !output_x!x!output_y!
rem echo compare "!scale_in:~0,3!"=="!scale_out:~0,3!"
rem echo !scale_in! vs !scale_out!
rem echo filter: !crop_filter!!resize_filter!
rem pause




rem --------------------------------

set motion_file_temp=motion_data_%random%%random%.tmp
if "!input_has_audio!"=="1" set final_input_mapping=-i !avs_temp! -i "!mkv_temp!" -map 0:v:0 -map 1:a:0



echo %cDEFAULT%
echo * %cGREEN%^(1/3^) %cCYAN%Processing the motion detection for the deshake filter...%cDEFAULT%
if "!show_cmdline!"=="1" echo %sGRAY%executing: bin\ffmpeg !ffmpeg_prepend! !ffmpeg_decoder_opts! !ts_start_secs! -i %input_motion% !duration_user! -vf "!mp_decimate_filter!vidstabdetect=shakiness=!shakiness_camera_factor!:accuracy=15:stepsize=6:mincontrast=0.3:result=!transforms_temp!" -f null -%cDEFAULT%&echo.
bin\ffmpeg !ffmpeg_prepend! !ffmpeg_decoder_opts! !ts_start_secs! -i %input_motion% !duration_user! -vf "!mp_decimate_filter!vidstabdetect=shakiness=!shakiness_camera_factor!:accuracy=15:stepsize=6:mincontrast=0.3:result=!transforms_temp!" -f null -
if ERRORLEVEL 1 echo fatal ffmpeg error! & call :fatal_error_pause

echo.
echo * %cGREEN%^(2/3^) %cCYAN%Rendering the deshaken, cropped and rescaled intermediary file...%cDEFAULT% "!mkv_temp!"
if "!show_cmdline!"=="1" echo %sGRAY%executing: bin\ffmpeg !ffmpeg_prepend! %ffmpeg_decoder_opts% !ts_start_secs! -i %input_motion% !duration_user! -vsync vfr -vf "!mp_decimate_filter!vidstabtransform=smoothing=!smooth_camera_factor!:interpol=linear:crop=black:zoom=!zoom!:input=!transforms_temp!,unsharp=5:5:0.8:3:3:0.4,format=yuv420p!crop_filter!!resize_filter!" !ffmpeg_encoder_opts! -preset fast -rc:v vbr_minqp -qmin:v 1 -qmax:v 18 "!mkv_temp!"%cDEFAULT%&echo.
bin\ffmpeg !ffmpeg_prepend! %ffmpeg_decoder_opts% !ts_start_secs! -i %input_motion% !duration_user! -vsync vfr -vf "!mp_decimate_filter!vidstabtransform=smoothing=!smooth_camera_factor!:interpol=linear:crop=black:zoom=!zoom!:input=!transforms_temp!,unsharp=5:5:0.8:3:3:0.4,format=yuv420p!crop_filter!!resize_filter!" !ffmpeg_encoder_opts! -preset fast -rc:v vbr_minqp -qmin:v 1 -qmax:v 18 "!mkv_temp!"
if ERRORLEVEL 1 echo fatal ffmpeg error! & call :fatal_error_pause


rem generate the avisynth script that does the motion interpolation
call :gen_avisynth_script

echo.
echo * %cGREEN%^(3/3^) %cCYAN%Rendering the final file with motion interpolation targeting !target_fps!fps.%cDEFAULT%
if "!show_cmdline!"=="1" echo %sGRAY%executing: bin\ffmpeg %ffmpeg_prepend% !final_input_mapping! !ffmpeg_encoder_opts! -rc:v vbr_minqp -qmin:v 1 -qmax:v !output_video_quality_ratefactor! "%output_motion%"%cDEFAULT%&echo.
bin\ffmpeg %ffmpeg_prepend% !final_input_mapping! !ffmpeg_encoder_opts! -rc:v vbr_minqp -qmin:v 1 -qmax:v !output_video_quality_ratefactor! "%output_motion%"
if ERRORLEVEL 1 echo fatal ffmpeg error! & call :fatal_error_pause


rem delete the ffindex file created with the mkv.
del "!mkv_temp!.ffindex" >NUL 2>NUL 

rem cleanup, delete temporary files
del "!transforms_temp!" >NUL 2>NUL
del !avs_temp! >NUL 2>NUL
del "!mkv_temp!" >NUL 2>NUL

echo.
echo %cGREEN%all done! %cYELLOW%%output_motion%


::aguardar 3 segundos
timeout 5 /nobreak >NUL 2>NUL
goto :eof




:: end of the main function
::================================================================
::================================================================
:: other functions and weird stuff
::================================================================
::================================================================

:fatal_error_pause
pause
exit
goto :eof

::================================================================
:test_thing
echo %cDEFAULT%%~1 %cCOLUMN%%cYELLOW%[...]
%~2 >NUL 2>NUL
if ERRORLEVEL 1 (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cRED%[FAIL]    
echo %cDEFAULT% %~3
set error_test_thing=1
exit /B
)else (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cGREEN%[OK]    
set error_test_thing=0
)
goto :eof

::================================================================
:test_thing_optional
echo %cDEFAULT%%~1 %cCOLUMN%%cYELLOW%[...]
%~2 >NUL 2>NUL
if ERRORLEVEL 1 (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cYELLOW%[not available]
echo %cDEFAULT% %~3
set error_test_thing=1
exit /B
)else (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cGREEN%[OK]    
set error_test_thing=0
)
goto :eof




::================================================================
:gen_avisynth_script

rem echo loadplugin^(^"%ProgramFiles(x86)%\AviSynth+\plugins64\ffms2.dll^"^) >%avs_temp%
echo loadplugin^(^"%cd%\avisynth_plugins\ffms2.dll^"^) >%avs_temp%
echo loadplugin^(^"%cd%\avisynth_plugins\mvtools2.dll^"^)>>%avs_temp%
echo SetFilterMTMode^(^"DEFAULT_MT_MODE^", 2^)>>%avs_temp%
echo SetFilterMTMode^(^"FFVideoSource^", 3^)>>%avs_temp%
rem echo A = FFAudioSource^(^"%input_motion%^"^)>>%avs_temp%
echo V = FFVideoSource^(^"!mkv_temp!^"^)>>%avs_temp%
rem echo source = AudioDub^(V, A^)>>%avs_temp%
echo source = V >>%avs_temp%
echo super = MSuper^(source, pel=2^)>>%avs_temp%
echo backward_vectors = MAnalyse^(super, blksize=8, overlap=4, isb=true, dct=1, search=3^)>>%avs_temp%
echo forward_vectors = MAnalyse^(super, blksize=8, overlap=4, isb=false, dct=1, search=3^)>>%avs_temp%
echo MFlowFps^(source, super, backward_vectors, forward_vectors, num=960000, den=1000, ml=100^)>>%avs_temp%
echo Merge^(SelectEven^(^), SelectOdd^(^)^,!frame_blending_mixing_weigth_f1!)>>%avs_temp%
echo Merge^(SelectEven^(^), SelectOdd^(^)^,!frame_blending_mixing_weigth_f2!)>>%avs_temp%
echo Merge^(SelectEven^(^), SelectOdd^(^)^,!frame_blending_mixing_weigth_f3!)>>%avs_temp%
echo Merge^(SelectEven^(^), SelectOdd^(^)^,!frame_blending_mixing_weigth_f4!)>>%avs_temp%

rem an extra merge of neighbor frames if the target is 30
if "!output_30_fps!"=="1" echo Merge^(SelectEven^(^), SelectOdd^(^)^,!frame_blending_mixing_weigth_f4!)>>%avs_temp%

echo Prefetch^(%NUMBER_OF_PROCESSORS%^)>>%avs_temp%
goto :eof

::================================================================
:gen_avisynth_test
echo Version^(^)>%avs_temp%
goto :eof


::================================================================
:gen_avisynth_plugin_test
echo loadplugin^(^"%cd%\avisynth_plugins\ffms2.dll^"^) >%avs_temp%
echo loadplugin^(^"%cd%\avisynth_plugins\mvtools2.dll^"^)>>%avs_temp%
echo Version^(^)>>%avs_temp%
goto :eof


::===================================================================
:format_float

set ff_str=%1
rem numero q vem antes da virgula
set /a ff_a=%1 / !fp!


rem its 0. everything else
if "!ff_a!"=="0" set ret_float=!ff_a!.%1& goto :eof


rem comprimento do numero completo
call :strlen %1
set ff_lenf=!ret_strlen!

rem comprimento do q vem antes da virgula
call :strlen !ff_a!
set /a ff_len1=!ff_lenf! - !ret_strlen!


rem numero antes virgula, virgula e resto da string

if "!ret_strlen!"=="1" set ret_float=!ff_a!.!ff_str:~1,%ff_len1%!
if "!ret_strlen!"=="2" set ret_float=!ff_a!.!ff_str:~2,%ff_len1%!
if "!ret_strlen!"=="3" set ret_float=!ff_a!.!ff_str:~3,%ff_len1%!
if "!ret_strlen!"=="4" set ret_float=!ff_a!.!ff_str:~4,%ff_len1%!


goto :eof

::================================================================
:strlen
set strlendata=%1
for /L %%x in (1,1,1000) do ( if "!strlendata:~%%x!"=="" set Lenght=%%x& goto strlen_result )
:strlen_result
set ret_strlen=!Lenght!
goto :eof

::===================================================================
:trim_zeroes
set num_ret=%1
 :loop_trim_zeroes 
 if "%num_ret:~0,1%"=="0" (
 set num_ret=%num_ret:~1,999%
 
 if "!num_ret!"=="0" (
 goto :eof
 )
  
 goto loop_trim_zeroes
 )
goto :eof

