/*
 * Copyright 2013 Exavideo LLC.
 * 
 * This file is part of Exaboard.
 * 
 * Exaboard is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * Exaboard is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with Exaboard.  If not, see <http://www.gnu.org/licenses/>.
 */


"use strict";
var autocompletePenalties = [];
var clockState = { };
var lastStopTimeElapsed = 0;
var last_clock_value;
var overtime_length = 5*60*10;
var schoolList = [];
var sportList = [];

function getText(sourceurl, callback) {
	jQuery.ajax({
		url: sourceurl,
		dataType: "text",
		error: function(jqxhr, textStatus) {
			console.log("Communication failure: " + textStatus);
		},
		success: function(data) {
			callback(data);
		}
	});
}


function getJson(sourceurl, callback) {
	jQuery.ajax({
		url: sourceurl,
		dataType: "json",
		error: function(jqxhr, textStatus) {
			console.log("Communication failure: " + textStatus);
		},
		success: function(data) {
			callback(data);
		}
	});
}

function putJson(desturl, obj) {
	jQuery.ajax({
		type: "PUT",
		url: desturl,
		contentType: "application/json",
		data: JSON.stringify(obj),
	});
}

function postJson(desturl, obj) {
	jQuery.ajax({
		type: "POST",
		url: desturl,
		contentType: "application/json",
		data: JSON.stringify(obj),
	});
}

function fieldsetToJson(fieldset) {
	var fields = fieldset.serializeArray();
	var result = { };
	$.each(fields, function(i, field) {
		result[field.name] = field.value;
	});

	return result;
}

function isInt(x) {
	var y = parseInt(x, 10);
	if (isNaN(y)) {
		return false;
	}

	return (x == y && x.toString() == y.toString());
}

function intOrZero(x) {
	if (isInt(x)) {
		return parseInt(x, 10);
	} else {
		return 0;
	}
}

function startClock(dummy) {
	// save the time for penalties
	lastStopTimeElapsed = clockState.time_elapsed;
	putJson('clock/running', { 'run' : true }); 
}

function stopClock(dummy) {
	putJson('clock/running', { 'run' : false });
}

function formatTime(tenthsClock) {
	var tenths = tenthsClock % 10;
	var seconds = Math.floor(tenthsClock / 10);
	var minutes = Math.floor(seconds / 60);
	seconds = seconds % 60;

	var result = minutes + ":";
	if (seconds < 10) {
		result += "0";
	} 
	result += seconds;
	result += "." + tenths;
	return result;
}

function formatTimeNoTenths(tenthsClock) {
	var seconds = Math.floor(tenthsClock / 10);
	var minutes = Math.floor(seconds / 60);
	var result = "";

	seconds = seconds % 60;

	if (minutes > 0) {
		result += minutes;
	}
	result += ":";
	if (seconds < 10) {
		result += "0";
	}
	result += seconds;
	return result;
}

function updateMainClock(data) {
	clockState = data;

	var tenthsRemaining = data.period_remaining;
	var period = data.period;
	var isRunning = data.running;

	if (last_clock_value != null && last_clock_value != tenthsRemaining) {
		/* the clock is moving, so clear any timeouts */
		$("#homeTeamControl").clearTimeout( );
		$("#awayTeamControl").clearTimeout( );
	}

	last_clock_value = tenthsRemaining;

	var clockField = $("#clockControl").find("#clock");
	var periodField = $("#clockControl").find("#period");

	if (isRunning) {
		clockField.addClass("clock_running");
		clockField.removeClass("clock_stopped");
		$("#toggleClock").css("border","2px solid #f00");
	} else {
		clockField.addClass("clock_stopped");
		clockField.removeClass("clock_running");
		$("#toggleClock").css("border","2px solid #0f0");
	}

	clockField.text(formatTime(tenthsRemaining));
	periodField.text(period);
}

function updatePlayClock(data) {
	$("#playClock").text(formatTimeNoTenths(data['time_remaining']));	
}

function updateClock( ) {
	getJson('clocks', function(data) {
		updateMainClock(data['game_clock']);
		updatePlayClock(data['play_clock']);
	});
}

function updateClockTimeout( ) {
	updateClock( );
	setTimeout(updateClockTimeout, 100);
}

function updatePreviewTimeout( ) {
	$('#scoreboardPreview').load('preview svg');
	setTimeout(updatePreviewTimeout, 500);
}

function updateGameStateTimeout( ) {
	getGameState( );
	$("#homeTeamControl").getTeamData( );
	$("#awayTeamControl").getTeamData( );
	setTimeout(updateGameStateTimeout, 1000);
}

function putTeamDataInterval( ) {
	$("#homeTeamControl").putTeamDataIfDirty( );
	$("#awayTeamControl").putTeamDataIfDirty( );
}


function getGameState( ) {
	getJson('gameState', function(data) {
		$("#downNumber").html(data['down']);
		$("#ytgNumber").html(data['distanceToGo']);

		/* this assumes no one will ever try a field goal from more than 60 */
		$("#fieldGoalDistance").val(data['ballPosition'] + 10);
	});
}

function putGameState( ) {
	// right now this is just down and distance,
	// but it can be used for other global data as well.
	var down = $("#downNumber").html();
	var ytg = getYTG();

	// put to server
	putJson('gameState', {
		'down': down,
		'distanceToGo': ytg
	});
}

jQuery.fn.buildTeamControl = function() {
	$(this).each(function(index, elem) {
		$(elem).html($("#teamProto").html());

		// hang onto this because jQuery will move it later
		$(elem).data(
			"penaltyDialog", 
			$(elem).find("#penalty_queue_dialog")
		);

		$(elem).find("#penalty_queue_dialog").data("team", $(elem));
		
		$(elem).find(".plusScore").click(function() {
			addPoints.call(this, $(this).attr("value"));
		}); 

		$(elem).find("#shotsPlusOne").click(shotTaken);
		$(elem).find("#possession").click(possessionChange);		
		
		$(elem).find(".penaltyBttn").click(function() { 
			newPenalty.call(this, $(this).attr("value"));
		});

		$(elem).find("#clearPenalties").click(clearPenalties);
		
		$(this).team()
			.penaltyDialog()
			.find("#clearAllPenalties")
			.click(clearPenalties);

		$(elem).find("#editPenalties").click(editPenalties);
		
		$(elem).find(".statusBttn").change(teamStatusChange);
		$(elem).find("#clearTeamStatus").click(teamStatusClear);

		$(elem).find(".teamStateCheckbox").change(function() {
			$(this).team().markDirtyTeamData();
		});
		
		$(elem).find("input[type=text],select").blur(function() {
			//updateTeamUI();
			$(this).team().markDirtyTeamData(); 
		});

		$(elem).find(".penalty_list").sortable({ 
			connectWith: $(elem).find(".penalty_list"),
			stop: function() { 
				console.log("sortable stop putting team data");
				$(this).team().markDirtyTeamData(); 
			}
		});
		$(elem).find(".penalty_queue").build_penalty_queue();
	});
}

jQuery.fn.build_penalty_queue = function() {
	$(this).each(function(index, elem) {
		$(elem).find("#now").click(penaltyQueueStartNow);
		$(elem).find("#last").click(penaltyQueueStartLastStop);
	});
}

jQuery.fn.team = function() {
	var teamControl = $(this).closest(".teamControl");

	if (teamControl.length == 0) {
		return $(this).closest("#penalty_queue_dialog").data("team");
	} else {
		return teamControl;
	}
}

jQuery.fn.penaltyQueue = function() {
	return $(this).closest(".penalty_queue");
}

jQuery.fn.penaltyDialog = function() {
	return $(this).data("penaltyDialog");
}

jQuery.fn.newPenaltyDiv = function() {
	var penaltyDiv = $(this).penaltyDialog().find("#penaltyProto").clone(true);
	penaltyDiv.removeAttr('id');
	penaltyDiv.find("#player").autocomplete({ 
		source: $(this).data('roster'),
		change: $(this).change()
	});
	penaltyDiv.find("#penalty").autocomplete({ 
		source: autocompletePenalties,
		change: $(this).change()
	});

	penaltyDiv.find("#announcePenalty").click(function() { 
		penaltyDiv.announcePenalty( );	 
	});
	penaltyDiv.find("#deletePenalty").click(deleteSinglePenalty);

	return penaltyDiv;
}
	

// newPenalty
// add a penalty to the team's penalty queue
function newPenalty(time) {
	var penaltyDiv = $(this).team().newPenaltyDiv();

	// set up penalty time correctly (creative selector abuse)
	penaltyDiv.find('select#time').val(time);

	// load announce strings
	penaltyDiv.find('input#player').val($(this).team().find('#penaltyPlayer').val());
	penaltyDiv.find('input#penalty').val($(this).team().find('#penaltyPenalty').val());
	$(this).team().find('#penaltyPlayer').val('')
	$(this).team().find('#penaltyPenalty').val('')

	// add to the shorter of the two penalty queues
	$(this).team().queuePenalty(penaltyDiv);

	// sync team data
	$(this).team().markDirtyTeamData();
}

// queuePenalty
jQuery.fn.queuePenalty = function(penalty_div) {
	var penaltyQueues = $(this).penaltyDialog().find(".penalty_queue");
	
	var min_queue_end = -1;
	var queue_with_min_end = 0;

	// find which queue has the shortest length
	penaltyQueues.each(function(i, q) {
		// flush expired penalties from queue
		$(q).penaltyQueueFlush( );

		var qend = $(q).penaltyQueueEnd();
		if (qend < min_queue_end || min_queue_end == -1) {
			min_queue_end = qend;
			queue_with_min_end = i;
		}
	});

	// queue the penalty
	var queue = penaltyQueues[queue_with_min_end]
	if ($(queue).penaltyQueueEnd() == 0) {
		// start penalty queue now if it had no penalties or just expired ones
		$(queue).penaltyQueueClear();
		$(queue).penaltyQueueStartNow();
	}

	$(queue).find(".penalty_list").append(penalty_div);
}

jQuery.fn.penaltyQueueFlush = function( ) {
	var penalty_end = $(this).find("#start").timeval();
	$(this).find(".penaltyData").each(function(i, p) {
		penalty_end = penalty_end + $(p).penaltyLength();
		console.log("penalty_end=" + penalty_end);
		console.log("time elapsed="+clockState.time_elapsed);
		if (penalty_end < clockState.time_elapsed) {
			console.log("flushing penalty??");
			// delete this expired penalty
			$(p).remove();
			// adjust queue start
			$(this).find("#start").timeval(penalty_end);
		}
	});
}

jQuery.fn.serializePenaltiesJson = function() {
	var json = { }
	json.activeQueueStarts = $(this).find(".penalty_queue").map(
		function(i,e) {
			return [$(e).find("#start").timeval()];
		}
	).get();
	json.activeQueues = $(this).find(".penalty_queue").map(
		function(i,e) {
			return [$(e).serializePenaltyListJson()];
		}
	).get();

	return json;
}

jQuery.fn.serializePenaltyListJson = function() {
	var json = this.find(".penaltyData").map(function(i,e) {
		return [$(e).serializeInputsJson()];
	}).get();

	return json;
}

jQuery.fn.announcePenalty = function( ) {
	var player = this.find("#player").val( );
	var penalty = this.find("#penalty").val( );
	var team = this.team( );

	var announces = [ team.find('#name').val( ) + ' PENALTY', player, penalty ];
	postJson('announce', { messages : announces });
}

jQuery.fn.unserializePenaltiesJson = function(data) {
	this.find(".penalty_queue").each(function(i,e) {
		if (i < data.activeQueueStarts.length) {
			$(e).find("#start").timeval(data.activeQueueStarts[i]);
		}

		if (i < data.activeQueues.length) {
			$(e).unserializePenaltyListJson(data.activeQueues[i]);
		}
	});
}

jQuery.fn.unserializePenaltyListJson = function(data) {
	var thiz = this;
	$(this).penaltyQueueClear( );
	jQuery.each(data, function(i,e) {		
		var penaltyDiv = $(thiz).team().newPenaltyDiv();
		penaltyDiv.unserializeInputsJson(e);
		$(thiz).find(".penalty_list").append(penaltyDiv);
	});
}


// Clear the penalty queue.
jQuery.fn.penaltyQueueClear = function() {
	$(this).find(".penaltyData").remove();
}

// Set the penalty queue's start time to now.
jQuery.fn.penaltyQueueStartNow = function() {
	$(this).find("#start").timeval(clockState.time_elapsed);
	$(this).team().markDirtyTeamData();
}

jQuery.fn.timeval = function(tv) {
	/* FIXME: allow for 20 min playoff overtimes */
	var period_length = 20*60*10;
	var n_periods = 3;

	if (typeof tv === 'number') {
		// set value
		var period = 0;
		var overtime = 0;

		console.log('parsing timeval ' + tv);

		while (tv >= period_length && period < n_periods) {
			tv -= period_length;
			period++;
		}

		console.log('period ' + period);

		while (period == n_periods && tv >= overtime_length) {
			tv -= overtime_length;
			overtime++;
		}

		console.log('overtime ' + overtime + ' length ' + overtime_length);

		var c_length;

		period = period + overtime;

		if (period >= n_periods) {
			c_length = overtime_length;
		} else {
			c_length = period_length;
		}
		
		tv = c_length - tv;

		console.log('tv ' + tv)

		this.val(formatTime(tv) + ' ' + (period+1));
	} else {
		// parse value
		var val = this.val( );
		var re = /((\d+):)?(\d+)(.(\d+))? (\d)/
		var result = re.exec(val);

		if (result) {
			var minutes = result[2];
			var seconds = result[3];
			var tenths = result[5];
			var period = result[6];
			var parsed = 0;
			var period_num = 0;
			var overtime_num = 0;
			var c_length = period_length;

			if (typeof minutes !== 'undefined') {
				parsed = parsed + parseInt(minutes, 10) * 600;
			}

			if (typeof seconds !== 'undefined') {
				parsed = parsed + parseInt(seconds, 10) * 10;
			}

			if (typeof tenths !== 'undefined') {
				parsed = parsed + parseInt(tenths, 10);
			}


			if (typeof period !== 'undefined') {
				period_num = parseInt(period, 10) - 1;
			} else {
				/* period_num = current period */
			}

			/* adjust for overtime */
			if (period_num >= 3) {
				overtime_num = period_num - 3;
				period_num = 3;
				c_length = overtime_length;
			}

			/* convert from time remaining to time elapsed */
			if (parsed > c_length) {
				parsed = c_length; 
			}
			parsed = c_length - parsed;
			
			parsed += period_num * period_length;
			parsed += overtime_num * overtime_length;

			return parsed;
		}
	}
}


// Find the time at which a penalty queue will end.
// e.g. $("#homeTeam #pq1").penaltyQueueEnd()
// Return zero if no penalties are on the queue or they are all expired.
jQuery.fn.penaltyQueueEnd = function() {
	var total = 0;
	var time = clockState.time_elapsed;
	var penalty_end = intOrZero($(this).find("#start").timeval());
	var count = 0;

	$(this).find(".penaltyData").each(function(i,e) {
		penalty_end = penalty_end + $(e).penaltyLength();
		count++;
	});

	if (penalty_end < time || count == 0) {
		return 0;
	} else {
		return penalty_end;
	}
}

// penaltyLength
// Find the length of a penalty...
// e.g. $("find_some_penalty_div").penaltyLength()
jQuery.fn.penaltyLength = function() {
	return parseInt($(this).find("select option:selected").val(), 10);
}


// clearPenalties
// Clear all penalties on a team.
function clearPenalties() {
	$(this).team().penaltyDialog().find(".penalty_queue .penaltyData").remove();
	$(this).team().markDirtyTeamData();
}

// editPenalties
// Bring up penalty queue dialog box for a team.
function editPenalties() {
	$(this).team().penaltyDialog().dialog('option', 'width', 700);
	$(this).team().penaltyDialog().dialog('open');
}

// penaltyQueueStartNow
// Start the penalty queue now.
function penaltyQueueStartNow() {
	$(this).penaltyQueue().penaltyQueueStartNow();
}

// penaltyQueueStartLastStop
// Set penalty queue start time to last play stoppage
function penaltyQueueStartLastStop() {
	$(this).penaltyQueue().find("#start").timeval(lastStopTimeElapsed);
}

function deleteSinglePenalty() {
	var pd = $(this).parents(".penaltyData");
	var tc = pd.team();
	pd.remove();
	tc.markDirtyTeamData();
}

// goalScored
// Stop clock and register a goal for the team.
function goalScored() {
	$(this).team().find("#score").val(
		intOrZero($(this).team().find("#score").val()) + 1
	);
	$(this).team().markDirtyTeamData();
	// trigger any kind of blinky goal animations (or whatever)
	viewCommand({"goal_scored_by" : $(this).team().data('url')});
}

// addPoints
// add points to a team's score
function addPoints(points) {
	$(this).team().find("#score").val(
		intOrZero($(this).team().find("#score").val()) +  parseInt(points)
	);
	$(this).team().markDirtyTeamData();
	// trigger any kind of blinky goal animations (or whatever)
	viewCommand({"goal_scored_by" : $(this).team().data('url')});
}

function shotTaken() {
	$(this).team().find("#shotsOnGoal").val(
		intOrZero($(this).team().find("#shotsOnGoal").val()) + 1
	);
	$(this).team().markDirtyTeamData();
}

function teamStatusClear() {
	// Clear all statuses
	if ($(this).attr("status") == "" ){
		$(this).team().find("#status").val("");
		$(this).team().find("#statusColor").val("");
		$(this).team().find(".statusBttn:checked").attr("checked", false);
	}
	$(this).team().markDirtyTeamData();
}

function teamStatusChange() {
	// Put up status of newly checked
	if ($(this).is(":checked")){
		$(this).team().find("#status").val($(this).attr("status"));
		$(this).team().find("#statusColor").val($(this).attr("color"));
	
	// on uncheck, look for other checked statuses from both teams
	} else {
		$(this).team().find("#status").val("");
		$(this).team().find("#status").val($(this).team().find(":checked").attr("status"));
		$(this).team().find("#statusColor").val($(this).team().find(":checked").attr("color"));
	}
	$(this).team().markDirtyTeamData();
}

function getYTG() {
	var ytg = $("#ytgNumber").html();
	var parsed = parseInt(ytg);
	if (isNaN(parsed)) {
		return ytg;
	} else {
		return parsed;
	}
}

function downUpdate() {
	var down = $("#downNumber").text();
	var ytg = getYTG();

	if ($(this).attr("id") == "nextDown") {
		if (down == "1st") { 
			down = "2nd"; 
		} else if (down == "2nd") {
			down = "3rd";
		} else if (down == "3rd") {
			down = "4th";
		} else if (down == "4th") {
			down = "1st"; 
			ytg = 10;
		}
	} else if ($(this).attr("id") == "firstAnd10") {
		down = "1st";
		ytg = 10;
	} else {
		down = $(this).attr("value");
	}
	
	$("#downNumber").html(down);
	$("#ytgNumber").html(ytg);

	putGameState();
}

function ytgUpdate() {
	var addSubYTG = 0;
	addSubYTG = $(this).attr("value");

	var down = $("#downNumber").html();
	var ytg = getYTG();
	
	if ($(this).attr("class") == "bttn addSubYTG") {
		if (ytg == "Goal") {
			// catches nth & Goal case; no change should be made
		} else if (ytg == "Inches" && addSubYTG > 0) {
			// catches nth & Inches; only increases value
			ytg = parseInt(0);
			ytg += parseInt(addSubYTG);		
		} else if (ytg + parseInt(addSubYTG) > 0 && ytg + parseInt(addSubYTG) < 90) {
			// values cannot be below 1 and above 89 because that's how football works
			ytg += parseInt(addSubYTG);
		}	
	} else if (addSubYTG == "Goal" || addSubYTG == "Inches") {
		ytg = addSubYTG;
	} else {
		// logic if hardcoded buttons are used
		ytg = parseInt(addSubYTG);
	}

	$("#downNumber").html(down);
	$("#ytgNumber").html(ytg); 

	putGameState();
}

function ytgCustom() {
	if ($(this).val() != "") { // prevents blank ytg
		var ytg = parseInt($(this).val());
		$("#ytgNumber").html(ytg);
		putGameState();
	}
}

function doDdDisplay(withPlayClock) {
	var down = $("#downNumber").html();
	var ytg = getYTG();
	$("#textInput").val(down + " & " + ytg);
	if (withPlayClock) {
		postStatusWithPlayClock();
	} else {
		postStatus();
	}
}

function ddDisplay() {
	doDdDisplay(false);
}

function ddDisplayWithPlayClock() {
	doDdDisplay(true);
}

function doFieldGoalDisplay(withPlayClock) {
	var distance = $("#fieldGoalDistance").val();
	if (withPlayClock) {
		$("#textInput").val(distance + " yd FG Att");
		postStatusWithPlayClock();
	} else {
		$("#textInput").val(distance + " yd FG Attempt");
		postStatus();
	}
}

function fieldGoalDisplay( ) {
	doFieldGoalDisplay(false);
}

function fieldGoalDisplayWithPlayClock() {
	doFieldGoalDisplay(true);
}

function possessionChange() {
	var this_poss = $(this).team().find("#possession");
	if (this_poss.is(':checked')) {
		$(".teamControl").each( function(index) {
			var other_poss = $(this).find("#possession");
			if (other_poss.get(0) !== this_poss.get(0)) {
				other_poss.prop('checked', false);
				$(this).markDirtyTeamData();
			}
		});
	}
}

// serializeInputsJson
// get values of all input fields within the matched elements as JSON
jQuery.fn.serializeInputsJson = function() {
	var result = { };
	$(this).find("input:text,select").each(function(i,e) {
		result[$(e).attr('id')] = $(e).val();
	});
	$(this).find("input:checkbox").each(function(i,e) {
		result[$(e).attr('id')] = $(e).is(':checked');
	});
	return result;
}

// serializeInputsJsonByName
// get values of all input fields within the matched elements as JSON
jQuery.fn.serializeInputsJsonByName = function() {
	var result = { };
	$(this).find("input:text,select").each(function(i,e) {
		result[$(e).attr('name')] = $(e).val();
	});
	$(this).find("input:checkbox").each(function(i,e) {
		result[$(e).attr('name')] = $(e).is(':checked');
	});
	return result;
}


// unserializeInputsJson
// take all properties of the object and try to set field values 
jQuery.fn.unserializeInputsJson = function(data) {
	for (var prop in data) {
		$(this).find("input#" + prop + ":text,select").val(data[prop]);
		$(this).find("select#" + prop).val(data[prop]);
		$(this).find("input#" + prop + ":checkbox").prop('checked', data[prop])
	}
}

jQuery.fn.getTeamData = function() {
	var thiz = this; // javascript can be counter-intuitive...
	var currentSerial = $(this).data('dataSerial');

	getJson($(this).data('url'), function(data) {
		// accept new data from the server only if its serial is bigger than 
		// what we have now, or if we don't have a serial (i.e. we haven't 
		// loaded any data yet)
		if (currentSerial == null || data.dataSerial > currentSerial) {
			$(thiz).unserializeInputsJson(data);
			// important to set roster before we unserialize penalties
			// else autocompletion might fail
			$(thiz).data("roster", data.autocompletePlayers);
			$(thiz).data("dataSerial", data.dataSerial);
			$(thiz).penaltyDialog().unserializePenaltiesJson(data.penalties);

			// data can't be dirty if we just pulled it
			$(thiz).data("dirty", 0);
		}
		updateTeamUI();
	});
}

// markDirtyTeamData
// Flag the team data as dirty (meaning that it needs to be uploaded
// to the server).
jQuery.fn.markDirtyTeamData = function() {
	$(this).data("dirty", 1);
}

jQuery.fn.markCleanTeamData = function() {
	$(this).data("dirty", 0);
}

// putTeamDataIfDirty
// If team data is dirty, put to server.
jQuery.fn.putTeamDataIfDirty = function() {
	if ($(this).data("dirty") != 0) {
		$(this).putTeamData();
		$(this).data("dirty", 0);
	}
}

// putTeamData
// Synchronize team data back to the server.
jQuery.fn.putTeamData = function() {
	//move this elsewhere (to scoreboard template?)
	// Check for Score/SOG being blanked
	// If so, reset value to 0 instead
	if ($(this).find("#score").val() <= 0) {
		$(this).find("#score").val(0);
	}

	// Propose a serial number of whatever the last one was, plus one.
	var json = $(this).serializeInputsJson();
	var newSerial = $(this).data("dataSerial") + 1;
	$(this).data("dataSerial", newSerial);

	json['dataSerial'] = newSerial;
	json['penalties'] = $(this).penaltyDialog().serializePenaltiesJson();

	// there is an outside chance the ajax will fail if the dataSerial is less
	// than the one on the server side. If it succeeds, then we agree with
	// the server, so we can update our serial number. If it fails, then
	// something must have been updated on the server side, so we will do
	// a getTeamData and the server side state will override any local 
	// changes

	var team_obj = this; // for use in ajax closures
	console.log("initiating PUT request for team data");
	jQuery.ajax({
		type: "PUT",
		url: $(this).data('url'),
		contentType: "application/json",
		data: JSON.stringify(json),
		success: function(data) {
			// update our dataSerial
			console.log("sent team data, received back data", data);
		},
		error: function(jqXHR, textStatus) {
			// trigger update on failure to push
			console.log("put request failed");
			$(team_obj).getTeamData();
		}
	});
}

jQuery.fn.clearTimeout = function() {
	var old_value = $(this).find("#timeout_").prop("checked");
	if (old_value) {
		/* if it was checked, clear the check box */
		$(this).find("#timeout_").prop("checked", false);
		/* then fire event handler to fix up status fields */
		$(this).find("#timeout_").change();
	}
}

function getSettings(){

}

function putSettings( ) {
	var json = $("#gameSettings").serializeInputsJson();
	putJson("scoreboardSettings", json);
}

function transitionScoreboard() {
	if ($(this).attr("status") == "up"){
		scoreboardUp();
		$(this).attr("status", "down");//.html("<span>DOWN</span>");
	}
	if ($(this).attr("status") == "down"){
		scoreboardDown();
		$(this).attr("status", "up");//.html("<span>UP</span>");
	}
	// sets display status on page load and keeps it honest during operation
	setTimeout(function(){
		getJson('view_status', function(data){
			$("#transitionControl").attr("checked", data.is_up);
		});
	}, 1100);

}

function announceStatusTextInput() {
	return $("#textInput").val();
}

function announceStatusColor() {
	return $("#textInputColor").val();
}

function postGlobalAnnounce() {
	postJson('announce', { message : announceStatusTextInput() });	 
}

function postGlobalStatus() {
	putJson('status', { message : announceStatusTextInput() });
}

function postStatusWithPlayClock() {
	putJson('status', { message: announceStatusTextInput(), enablePlayClock: true });
}

function postStatusWithColor() {
	putJson('status', { message : announceStatusTextInput(), color : announceStatusColor() });
}

function clearGlobalStatus() {
	putJson('status', { message : "" });
	$("#textInput").val("");
}

function viewCommand(cmd) {
	putJson('view_command', cmd);
}

function scoreboardUp() {
	viewCommand({'up':1});
}

function scoreboardDown() {
	viewCommand({'down':1});
}

function globalNextAnnounce() {
	viewCommand({'announce_next':1});
}

function setClock() {
	putJson('clock', $("#clockSet").serializeInputsJson());
}

function toggleClock() {
	putJson('clock/toggle', {});
}

function adjustClock(time) {
	putJson('clock/adjust', { 'time' : time });
}

function periodAdvance(dummy) {
	putJson('clock/advance', {});
}

function changeAutosync() {
	putJson('autosync', {
		'clock' : $('#syncClock').is(':checked'),
		'score' : $('#syncScore').is(':checked'),
		'other' : $('#syncOther').is(':checked')
	});
}

function getAutosync() {
	getJson('autosync', function(data) {
		$('#syncClock').prop('checked', data.clock);
		$('#syncScore').prop('checked', data.score);
		$('#syncOther').prop('checked', data.other);
	});
}

function showHideSettings() {
	$(".settingsBox").toggle("blind", 1000);

	if ($("#toggleSettingsText").html() == "Hide <u>S</u>ettings") {
		$("#toggleSettingsText").html("Show <u>S</u>ettings");
		// Reload Team Data
		//This needs to be handled outside of this function
		$("#awayTeamControl").data('url','team/0');
		$("#awayTeamControl").getTeamData();
		$("#homeTeamControl").data('url','team/1');
		$("#homeTeamControl").getTeamData();
	} else {
		$("#toggleSettingsText").html("Hide <u>S</u>ettings");
	}
}

function generateSportList() {
	$(this).autocomplete({
		create: function(event, ui){
			$.getJSON("js/sports.json", function(list){
				$.each(list.sport, function (k,v){
					sportList[k] = v.gameType;
				});
			});
		},
		autoFocus: true,
		source: sportList,
		select: function(event, ui) {
			$.getJSON("js/sports.json", function(list){
				$.each(list.sport, function (k,v){
					if (v.gameType == ui.item.value){
						$("#gameSettings").unserializeInputsJson(v);
						putSettings();
						var currentSport = $("#sportClassName").val();
						$(".baseball, .basketball, .broomball, .football, .hockey, .lacrosse, .rugby, .soccer, .volleyball").fadeOut();
						$('.' + currentSport).fadeIn();
						$("#resetOnChangeDialog").dialog('open');
						document.title = ('Exaboard - ' + $("#gameType").val());
					}
				});
			});
		}
	}); 
}

function getSettingsPresets(event, ui) {
	//some implementation of unserializeJson should go here
	$.getJSON("js/sports.json", function(list){
		$.each(list.sports, function (k,v){
			if (v.gameType == ui.item.value){
				alert(v.periodQty);
			}
		});
	});
}

function changeSyncSettings() {
	var json = $("#syncSettings").serializeInputsJsonByName();
	if (json['baud'].trim() == "") {
		delete json['baud'];
	}

	if (json['port'].trim() == "") {
		delete json['port'];
	}

	putJson("sync_mode", json);
}
	
function setGlobalStatus() {
	$("#textInput").val($(this).attr("status"));
	$("#textInputColor").val($(this).attr("color"));
	postStatusWithColor();
}

function resetTeamData() {
	putJson("reset_teams", {});
	$("#resetOnChangeDialog").dialog('close');
}

function statusBttnColor(){
	$('.statusBttn, .globalStatusBttn').each(function (){
		$(this).closest('div').each(function(){
			var newBorderColor = '2px solid ' + $(this).find('input').attr('color');
			$(this).css('border', newBorderColor);
		})
	});
}

function keyBinding(){
	// causes checkboxes(statusBttns) to lose focus after clicked to avoid binding conflicts.
	$(":checkbox").change(function(){
		$(this).blur();
	});
	
	$(document).keydown(function(e){
		if (e.keyCode == 13 && $(document.activeElement).filter("input").length != 1) {
			toggleClock();
		}
		
		if (e.keyCode == 32 && $(document.activeElement).filter("input").length != 1) {
			$("#transitionControl").trigger("click");
		}
		
		if (e.keyCode == 83 && $(document.activeElement).filter("input").length != 1) {
			showHideSettings();
		}
	});
}

function autocompleteSchools(){
	$.getJSON("js/teamlist.json", function(teamlist) {
		$.each(teamlist.teams, function(k, v) {
			schoolList[k] = v.name;
		});

		$("#awayTeamControl").find("#teamSelect").val("").autocomplete({ 
			autoFocus:true,
			source: schoolList,
			select: function(event, ui){
				 $.getJSON('js/teamlist.json', function(list) {
					$.each(list.teams, function(k, v) {
						if (v.name == ui.item.value){
							$("#awayTeamControl").find("#name").val(v.abbreviation);
							$("#awayTeamControl").find("#bgcolor").val(v.color1);
							$("#awayTeamControl").find("#fgcolor").val(v.color1);
							$("#awayTeamControl").find("#nickname").val(v.nickname);
							$("#awayTeamControl").find("#logo").val(v.logo);
						}
					});
				});
				$("#awayTeamControl").find("#name, #bgcolor, #fgcolor, #nickname, #logo, #teamSelect").trigger("blur");
					
			}
		});

		$("#homeTeamControl").find("#teamSelect").val("").autocomplete({ 
			autoFocus:true,
			source: schoolList,
			select: function(event, ui){
				 $.getJSON('js/teamlist.json', function(list) {
					$.each(list.teams, function(k, v) {
						if (v.name == ui.item.value){
							$("#homeTeamControl").find("#name").val(v.abbreviation);
							$("#homeTeamControl").find("#bgcolor").val(v.color1);
							$("#homeTeamControl").find("#fgcolor").val(v.color1);
							$("#homeTeamControl").find("#nickname").val(v.nickname);
							$("#homeTeamControl").find("#logo").val(v.logo);
						}
					});
				});
				$("#homeTeamControl").find("#name, #bgcolor, #fgcolor, #nickname, #logo, #teamSelect").trigger("blur");
			}
		});
	});
}

function updateTeamUI(){

	$('.teamControlBox').each(function(){
		var color = $(this).find('#bgcolor').val()
		var newBorderColor = '5px solid ' + color;
		
		$(this).css('border', newBorderColor);
		$(this).find('span.teamName').html($(this).find('#name').val()).css('color',color);
	})
	//$(thiz).parent().css("border", "5px solid " + data.bgcolor); // Set team colors on panel
//$(thiz).parent().find("span.teamName").css("color", data.bgcolor);
	//$(thiz).parent().find("span.teamName").html(data.name); // Set team names on panel
}

$(document).ready(function() {
	updateClockTimeout( );
	updatePreviewTimeout( );
	updateGameStateTimeout( );

	// try to put dirty team data every 50ms
	setInterval(putTeamDataInterval, 50);

	getAutosync( );
	
	$(".teamControl").buildTeamControl();
	// set up team URLs and load initial data
	$("#awayTeamControl").data('url','team/0');
	$("#awayTeamControl").getTeamData();
	$("#homeTeamControl").data('url','team/1');
	$("#homeTeamControl").getTeamData();
	$(".dialog").dialog({
		autoOpen: false,
		modal: true,
		resizable: false,
	});

	$("#gameSettings").change(putSettings);
	transitionScoreboard.call(this);
	
	keyBinding();
	statusBttnColor();
	$("#toggleSettings").click(showHideSettings);
	// GENERATE LIST OF SCHOOLS FOR AUTOCOMPLETE FROM JSON
	autocompleteSchools();
	
	$("#gameType").click(generateSportList);
	
	//sets to a specific gametype
	//this will be rectified in future when getSettings() is working
	$(".baseball, .basketball, .broomball, .football, .hockey, .lacrosse, .rugby, .soccer, .volleyball").hide();
	$(".hockey").show();

	$("#toggleClock").click(toggleClock);
	$("#upSec").click( function() { adjustClock.call(this, 1000); } );
	$("#dnSec").click( function() { adjustClock.call(this, -1000); } );
	$("#upTenth").click( function() { adjustClock.call(this, 100); } );
	$("#dnTenth").click( function() { adjustClock.call(this, -100); } );
	$("#periodAdvance").click(periodAdvance);
	$("#setClock").click(setClock);
	$(".syncSetting").change(changeAutosync);
	
	$("#globalAnnounceBttn").click(postGlobalAnnounce);
	$("#globalStatusBttn").click(postGlobalStatus);
	$("#clearGlobalStatusBttn").click(clearGlobalStatus);
	$("#globalNextAnnounceBttn").click(globalNextAnnounce);

	$("#transitionControl").click(transitionScoreboard);
	
	$(".bttn.downs, .bttn.nextDown, .bttn.firstAnd10").click(downUpdate);
	$(".bttn.ytg, .bttn.ytgSpecial, .bttn.addSubYTG").click(ytgUpdate);
	$("#customYTG").change(ytgCustom);
	$("#displayDownDistance").click(ddDisplay);
	$("#displayDownDistanceWithPlayClock").click(ddDisplayWithPlayClock);
	$("#displayFieldGoalAttempt").click(fieldGoalDisplay);
	$("#displayFieldGoalAttemptWithClock").click(fieldGoalDisplayWithPlayClock);
	$("#syncSettings").find("select, input").change(changeSyncSettings);

	$(".globalStatusBttn").click(setGlobalStatus);
	$("#resetTeamData").click(resetTeamData);
	$("#closeResetOnChangeDialog").click(function() { $("#resetOnChangeDialog").dialog('close'); });
});
