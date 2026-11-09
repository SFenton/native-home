#if DEBUG
// Generated once from the app's house shape, every key and value replaced by a neutral demo value. Not edited by hand.
// The generator, the real-to-demo mapping and the real-id list stay outside the repository (ignored `build/demo/`).

extension DemoHouse {
    /// The demo house document as JSON (schema 2), decoded by ``DemoHouse/config``.
    static let documentJSON = #"""
{
 "bedroom": {
  "beds": [
   {
    "alarmSnoozeButtonEntityId": "button.demo_bedroom_1_alarm_1",
    "alarmStateEntityId": "sensor.demo_bedroom_1_alarm_1",
    "alarmStopButtonEntityId": "button.demo_bedroom_1_alarm_2",
    "breathingRateEntityId": "sensor.demo_sensor_1",
    "climateEntityId": "climate.demo_climate_1",
    "heartRateEntityId": "sensor.demo_sensor_2",
    "hotFlashActiveEntityId": "input_boolean.demo_input_boolean_1",
    "hotFlashButtonEntityId": "input_button.demo_input_button_1",
    "hotFlashCancelButtonEntityId": "input_button.demo_input_button_2",
    "hotFlashRestoreAtEntityId": "input_datetime.demo_input_datetime_1",
    "hotFlashTimerEntityId": "timer.demo_timer_1",
    "hrvEntityId": "sensor.demo_sensor_3",
    "id": "alexs-bed",
    "outsideScheduleScript": "demo_bed_alex_temperature_outside_schedule",
    "owner": "resident_1",
    "pumpClogEntityId": "binary_sensor.demo_binary_sensor_1",
    "pumpLoopTemperatureEntityId": "sensor.demo_sensor_4",
    "pumpRpmEntityId": "sensor.demo_sensor_5",
    "pumpStallEntityId": "binary_sensor.demo_binary_sensor_2",
    "schedulePhaseEntityId": "sensor.demo_schedule_1",
    "side": "left",
    "stageLevelEntityIds": {
     "asleep": "input_number.demo_level_1",
     "bedtime": "input_number.demo_level_2",
     "dawn": "input_number.demo_level_3"
    },
    "targetLevelEntityId": "number.demo_bedroom_1_level_1",
    "title": "Alex's Bed",
    "tonightScript": "demo_bed_alex_temperature_tonight"
   },
   {
    "alarmSnoozeButtonEntityId": "button.demo_bedroom_1_alarm_3",
    "alarmStateEntityId": "sensor.demo_bedroom_1_alarm_2",
    "alarmStopButtonEntityId": "button.demo_bedroom_1_alarm_4",
    "breathingRateEntityId": "sensor.demo_sensor_6",
    "climateEntityId": "climate.demo_climate_2",
    "heartRateEntityId": "sensor.demo_sensor_7",
    "hotFlashActiveEntityId": "input_boolean.demo_input_boolean_2",
    "hotFlashButtonEntityId": "input_button.demo_input_button_3",
    "hotFlashCancelButtonEntityId": "input_button.demo_input_button_4",
    "hotFlashRestoreAtEntityId": "input_datetime.demo_input_datetime_2",
    "hotFlashTimerEntityId": "timer.demo_timer_2",
    "hrvEntityId": "sensor.demo_sensor_8",
    "id": "sams-bed",
    "outsideScheduleScript": "demo_bed_sam_temperature_outside_schedule",
    "owner": "resident_2",
    "pumpClogEntityId": "binary_sensor.demo_binary_sensor_3",
    "pumpLoopTemperatureEntityId": "sensor.demo_sensor_9",
    "pumpRpmEntityId": "sensor.demo_sensor_10",
    "pumpStallEntityId": "binary_sensor.demo_binary_sensor_4",
    "schedulePhaseEntityId": "sensor.demo_schedule_2",
    "side": "right",
    "stageLevelEntityIds": {
     "asleep": "input_number.demo_level_4",
     "bedtime": "input_number.demo_level_5",
     "dawn": "input_number.demo_level_6"
    },
    "targetLevelEntityId": "number.demo_bedroom_1_level_2",
    "title": "Sam's Bed",
    "tonightScript": "demo_bed_sam_temperature_tonight"
   }
  ],
  "hotFlashBrokerScript": "demo_bed_hot_flash_broker",
  "householdAwayEntityId": "sensor.demo_status_1",
  "householdAwayScript": "demo_household_away_command",
  "scheduleEntityId": "sensor.demo_bedroom_1_1",
  "scheduleSetTopic": "bed/bed/cmd/set-schedules",
  "wakeLight": {
   "id": "bedroom-1",
   "roomTitle": "Bedroom 1",
   "sources": [
    {
     "alarmLabel": "Alex's Alarm",
     "alarmsLabel": "Alex's Alarms",
     "bedId": "alexs-bed",
     "id": "sleepypod:left",
     "side": "left"
    },
    {
     "alarmLabel": "Sam's Alarm",
     "alarmsLabel": "Sam's Alarms",
     "bedId": "sams-bed",
     "id": "sleepypod:right",
     "side": "right"
    }
   ],
   "statusEntityId": "sensor.demo_bedroom_1_light_1",
   "title": "Wake-Light Alarms"
  }
 },
 "chores": {
  "adminTodoEntityId": "todo.demo_todo_1",
  "adminTodoUploadPath": "/api/demo_admin_todo",
  "groceryEntityId": "todo.demo_todo_2",
  "pages": [
   {
    "addAction": {
     "assignedTask": {
      "defaultAssignee": ""
     }
    },
    "emptyDescription": "You have no chores due. Nice job!",
    "emptyTitle": "No Chores Due",
    "hasTaskForm": true,
    "hiddenByVacation": true,
    "hideListHeaders": false,
    "id": "chores",
    "lists": [
     {
      "entityId": "todo.demo_todo_3",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Past Due",
      "userIds": [
       "demo-user-alex"
      ]
     },
     {
      "entityId": "todo.demo_todo_4",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Evening Tasks",
      "userIds": [
       "demo-user-alex"
      ]
     },
     {
      "entityId": "todo.demo_todo_5",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Afternoon Tasks",
      "userIds": [
       "demo-user-alex"
      ]
     },
     {
      "entityId": "todo.demo_todo_6",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Morning Tasks",
      "userIds": [
       "demo-user-alex"
      ]
     },
     {
      "entityId": "todo.demo_todo_7",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Due Any Time Today",
      "userIds": [
       "demo-user-alex"
      ]
     },
     {
      "entityId": "todo.demo_todo_8",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "No Due Date",
      "userIds": [
       "demo-user-alex"
      ]
     },
     {
      "entityId": "todo.demo_todo_9",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Evening Tasks",
      "userIds": [
       "demo-user-sam"
      ]
     },
     {
      "entityId": "todo.demo_todo_10",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Afternoon Tasks",
      "userIds": [
       "demo-user-sam"
      ]
     },
     {
      "entityId": "todo.demo_todo_11",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Morning Tasks",
      "userIds": [
       "demo-user-sam"
      ]
     },
     {
      "entityId": "todo.demo_todo_12",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Due Any Time Today",
      "userIds": [
       "demo-user-sam"
      ]
     },
     {
      "entityId": "todo.demo_todo_13",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "No Due Date",
      "userIds": [
       "demo-user-sam"
      ]
     },
     {
      "entityId": "todo.demo_todo_14",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Upcoming",
      "userIds": [
       "demo-user-alex"
      ]
     },
     {
      "entityId": "todo.demo_todo_15",
      "hideCompleted": true,
      "hideWhenNoOpenItems": true,
      "title": "Upcoming",
      "userIds": [
       "demo-user-sam"
      ]
     }
    ],
    "title": "Chores"
   },
   {
    "addAction": {
     "groceryItem": {
      "entityId": "todo.demo_todo_2"
     }
    },
    "emptyDescription": "Add some groceries to see them appear.",
    "emptyTitle": "No Groceries Listed",
    "hasTaskForm": false,
    "hiddenByVacation": false,
    "hideListHeaders": false,
    "id": "groceries",
    "lists": [
     {
      "entityId": "todo.demo_todo_2",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Grocery List",
      "userIds": []
     }
    ],
    "title": "Groceries"
   },
   {
    "addAction": {
     "assignedTask": {
      "defaultAssignee": "1"
     }
    },
    "emptyDescription": "Alex has no chores due. Nice job!",
    "emptyTitle": "No Chores Due",
    "hasTaskForm": true,
    "hiddenByVacation": true,
    "hideListHeaders": false,
    "id": "alexs-chores",
    "lists": [
     {
      "countBucket": {
       "overdue": {}
      },
      "entityId": "todo.demo_todo_3",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Past Due",
      "userIds": []
     },
     {
      "countBucket": {
       "upcoming": {}
      },
      "entityId": "todo.demo_todo_16",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Due Today",
      "userIds": []
     },
     {
      "countBucket": {
       "upcoming": {}
      },
      "entityId": "todo.demo_todo_17",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Upcoming",
      "userIds": []
     },
     {
      "countBucket": {
       "noDueDate": {}
      },
      "entityId": "todo.demo_todo_8",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "No Due Date",
      "userIds": []
     }
    ],
    "resident": "resident_1",
    "title": "Alex's Chores"
   },
   {
    "addAction": {
     "assignedTask": {
      "defaultAssignee": "2"
     }
    },
    "emptyDescription": "Sam has no chores due. Nice job!",
    "emptyTitle": "No Chores Due",
    "hasTaskForm": true,
    "hiddenByVacation": true,
    "hideListHeaders": false,
    "id": "sams-chores",
    "lists": [
     {
      "countBucket": {
       "overdue": {}
      },
      "entityId": "todo.demo_todo_18",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Past Due",
      "userIds": []
     },
     {
      "countBucket": {
       "upcoming": {}
      },
      "entityId": "todo.demo_todo_19",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Due Today",
      "userIds": []
     },
     {
      "countBucket": {
       "upcoming": {}
      },
      "entityId": "todo.demo_todo_20",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Upcoming",
      "userIds": []
     },
     {
      "countBucket": {
       "noDueDate": {}
      },
      "entityId": "todo.demo_todo_13",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "No Due Date",
      "userIds": []
     }
    ],
    "resident": "resident_2",
    "title": "Sam's Chores"
   },
   {
    "addAction": {
     "assignedTask": {
      "defaultAssignee": ""
     }
    },
    "emptyDescription": "There are no unassigned chores due. Nice job!",
    "emptyTitle": "No Chores Due",
    "hasTaskForm": true,
    "hiddenByVacation": true,
    "hideListHeaders": false,
    "id": "unassigned-chores",
    "lists": [
     {
      "countBucket": {
       "overdue": {}
      },
      "entityId": "todo.demo_todo_21",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Past Due",
      "userIds": []
     },
     {
      "countBucket": {
       "upcoming": {}
      },
      "entityId": "todo.demo_todo_22",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Due Today",
      "userIds": []
     },
     {
      "countBucket": {
       "upcoming": {}
      },
      "entityId": "todo.demo_todo_23",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Upcoming",
      "userIds": []
     },
     {
      "countBucket": {
       "noDueDate": {}
      },
      "entityId": "todo.demo_todo_24",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "No Due Date",
      "userIds": []
     }
    ],
    "title": "Unassigned Chores"
   },
   {
    "addAction": {
     "assignedTask": {
      "defaultAssignee": "3"
     }
    },
    "emptyDescription": "There are no home improvement tasks due. Nice job!",
    "emptyTitle": "No Tasks Due",
    "hasTaskForm": true,
    "hiddenByVacation": true,
    "hideListHeaders": false,
    "id": "home-improvement-chores",
    "lists": [
     {
      "countBucket": {
       "overdue": {}
      },
      "entityId": "todo.demo_todo_25",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Past Due",
      "userIds": []
     },
     {
      "countBucket": {
       "upcoming": {}
      },
      "entityId": "todo.demo_todo_26",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Due Today",
      "userIds": []
     },
     {
      "countBucket": {
       "upcoming": {}
      },
      "entityId": "todo.demo_todo_27",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Upcoming",
      "userIds": []
     },
     {
      "countBucket": {
       "noDueDate": {}
      },
      "entityId": "todo.demo_todo_28",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "No Due Date",
      "userIds": []
     }
    ],
    "title": "Home Improvement Tasks"
   },
   {
    "addAction": {
     "adminTodo": {
      "entityId": "todo.demo_todo_1"
     }
    },
    "emptyDescription": "Use Add Task to create an admin to-do.",
    "emptyTitle": "No To-Do Tasks",
    "hasTaskForm": false,
    "hiddenByVacation": false,
    "hideListHeaders": true,
    "id": "to-do",
    "lists": [
     {
      "completionScript": "script.demo_script_1",
      "entityId": "todo.demo_todo_1",
      "hideCompleted": true,
      "hideWhenNoOpenItems": false,
      "title": "Admin To-Do",
      "userIds": []
     }
    ],
    "title": "To-Do"
   }
  ],
  "people": [
   {
    "haUserId": "demo-user-alex",
    "key": "resident_1",
    "name": "Alex",
    "personEntityId": "person.demo_alex",
    "seesAdminTodo": true,
    "soloTripId": "alex",
    "summaryLists": {
     "dueToday": "todo.demo_todo_16",
     "noDueDate": "todo.demo_todo_8",
     "overdue": "todo.demo_todo_3"
    },
    "taskAssignee": "1"
   },
   {
    "haUserId": "demo-user-sam",
    "key": "resident_2",
    "name": "Sam",
    "personEntityId": "person.demo_sam",
    "seesAdminTodo": false,
    "soloTripId": "sam",
    "summaryLists": {
     "dueToday": "todo.demo_todo_19",
     "noDueDate": "todo.demo_todo_13",
     "overdue": "todo.demo_todo_18"
    },
    "taskAssignee": "2"
   }
  ],
  "quickLinks": [
   {
    "countsGroceries": true,
    "pageId": "groceries",
    "tint": {
     "blue": 72,
     "green": 67,
     "red": 155
    },
    "title": "Groceries"
   },
   {
    "countsGroceries": false,
    "pageId": "alexs-chores",
    "resident": "resident_1",
    "tint": {
     "blue": 120,
     "green": 96,
     "red": 0
    },
    "title": "Alex's Tasks"
   },
   {
    "countsGroceries": false,
    "pageId": "sams-chores",
    "resident": "resident_2",
    "tint": {
     "blue": 0,
     "green": 108,
     "red": 212
    },
    "title": "Sam's Tasks"
   },
   {
    "countsGroceries": false,
    "pageId": "unassigned-chores",
    "tint": {
     "blue": 126,
     "green": 58,
     "red": 81
    },
    "title": "Unassigned Tasks"
   },
   {
    "countsGroceries": false,
    "pageId": "home-improvement-chores",
    "tint": {
     "blue": 154,
     "green": 143,
     "red": 64
    },
    "title": "Home Tasks"
   }
  ],
  "vacationEmptyDescription": "Enjoy vacation!"
 },
 "climate": {
  "awayModeEntityId": "binary_sensor.demo_contact_1",
  "contactSensors": [
   {
    "entityId": "binary_sensor.demo_front_door_contact_1",
    "title": "Front Door"
   },
   {
    "entityId": "binary_sensor.demo_office_contact_1",
    "title": "Computer Window"
   },
   {
    "entityId": "binary_sensor.demo_office_contact_2",
    "title": "Office Window"
   },
   {
    "entityId": "binary_sensor.demo_living_room_contact_1",
    "title": "Living Room Window"
   },
   {
    "entityId": "binary_sensor.demo_garage_contact_1",
    "title": "Garage Door"
   },
   {
    "entityId": "binary_sensor.demo_bedroom_1_contact_1",
    "title": "Bedroom 1 Windows"
   },
   {
    "entityId": "binary_sensor.demo_dining_room_contact_1",
    "title": "Dining Room Door"
   },
   {
    "entityId": "binary_sensor.demo_kitchen_contact_1",
    "title": "Kitchen Door"
   },
   {
    "entityId": "binary_sensor.demo_studio_contact_1",
    "title": "Studio Door"
   },
   {
    "entityId": "binary_sensor.demo_media_room_contact_1",
    "title": "Media room Door"
   },
   {
    "entityId": "binary_sensor.demo_guest_room_contact_1",
    "title": "Guest Room Window"
   },
   {
    "entityId": "binary_sensor.demo_gym_contact_1",
    "title": "Gym Window"
   }
  ],
  "coolColorHex": 2920088,
  "ecoAwayEntityId": "select.demo_contact_1",
  "ecoAwayThermostatEntityId": "climate.demo_contact_1",
  "ecoCriticalEntityId": "select.demo_contact_2",
  "ecoModeEntityId": "switch.demo_contact_1",
  "globalThermostatEntityId": "climate.demo_contact_2",
  "heatColorHex": 13456385,
  "homeAwayEntityId": "sensor.demo_away_1",
  "homeAwayReasonEntityId": "sensor.demo_away_2",
  "hubEntityId": "climate.demo_climate_3",
  "integrationEntityId": "input_boolean.demo_contact_1",
  "predictiveAllowAwayEntityId": "switch.demo_contact_2",
  "predictiveAutoAdjustEntityId": "switch.demo_contact_3",
  "predictiveComfortEntityId": "switch.demo_contact_4",
  "predictiveHvacModeChangesEntityId": "switch.demo_contact_5",
  "predictiveSensorEntityId": "sensor.demo_living_room_contact_1",
  "rooms": [
   {
    "occupiedOnlyEntityId": "switch.demo_living_room_occupied_only",
    "title": "Living Room",
    "ventEntityIds": [
     "cover.demo_living_room_vent_1",
     "cover.demo_living_room_vent_2"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_office_occupied_only",
    "title": "Office",
    "ventEntityIds": [
     "cover.demo_office_vent_1"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_bedroom_1_occupied_only",
    "title": "Bedroom 1",
    "ventEntityIds": [
     "cover.demo_bedroom_1_vent_1",
     "cover.demo_bedroom_1_vent_2"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_bathroom_1_occupied_only",
    "title": "Bathroom 1",
    "ventEntityIds": [
     "cover.demo_bathroom_1_vent_1"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_kitchen_occupied_only",
    "title": "Kitchen",
    "ventEntityIds": [
     "cover.demo_kitchen_vent_1"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_guest_room_occupied_only",
    "title": "Guest Room",
    "ventEntityIds": [
     "cover.demo_guest_room_vent_1"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_dining_room_occupied_only",
    "title": "Dining Room",
    "ventEntityIds": [
     "cover.demo_dining_room_vent_1"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_gym_occupied_only",
    "title": "Gym",
    "ventEntityIds": [
     "cover.demo_gym_vent_1"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_guest_bathroom_occupied_only",
    "title": "Guest Bathroom",
    "ventEntityIds": [
     "cover.demo_vent_1"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_studio_occupied_only",
    "title": "Studio",
    "ventEntityIds": [
     "cover.demo_studio_vent_1"
    ]
   },
   {
    "occupiedOnlyEntityId": "switch.demo_media_room_occupied_only",
    "title": "Media room",
    "ventEntityIds": [
     "cover.demo_media_room_vent_1",
     "cover.demo_media_room_vent_2"
    ]
   }
  ],
  "trackSelectCriticalOption": "Track Select Critical",
  "trackSelectedEntityId": "switch.demo_contact_6"
 },
 "customLights": {
  "customMode": "Custom",
  "fallbackModes": [
   "Default",
   "Custom",
   "Team Colors",
   "Holiday Mode"
  ],
  "groupEntityId": "light.demo_front_yard_1",
  "lightingModeTitle": "Lighting Mode",
  "lights": [
   {
    "entityId": "light.demo_front_door_door_1",
    "title": "Left Door Light"
   },
   {
    "entityId": "light.demo_front_door_door_2",
    "title": "Right Door Light"
   },
   {
    "entityId": "light.demo_front_door_door_3",
    "title": "Path Light 1"
   },
   {
    "entityId": "light.demo_front_door_door_4",
    "title": "Path Light 2"
   },
   {
    "entityId": "light.demo_front_door_door_5",
    "title": "Path Light 3"
   },
   {
    "entityId": "light.demo_front_door_door_6",
    "title": "Path Light 4"
   },
   {
    "entityId": "light.demo_front_door_door_7",
    "title": "Path Light 5"
   },
   {
    "entityId": "light.demo_front_door_door_8",
    "title": "Path Light 6"
   }
  ],
  "manualControlEntityId": "input_boolean.demo_front_yard_1",
  "modeEntityId": "input_select.demo_front_yard_1",
  "sectionTitle": "Front Yard"
 },
 "food": {
  "allFoodTint": {
   "blue": 94,
   "green": 128,
   "red": 88
  },
  "allRecipesTint": {
   "blue": 180,
   "green": 126,
   "red": 42
  },
  "expiredItemsEntityId": "sensor.demo_expired_items_1",
  "expiringSoonEntityId": "sensor.demo_sensor_11",
  "spaces": [
   {
    "blue": 64,
    "entityId": "sensor.demo_sensor_12",
    "green": 110,
    "icon": "mdi:food-fork-drink",
    "location": "dispensa",
    "red": 155,
    "title": "Pantry"
   },
   {
    "blue": 180,
    "entityId": "sensor.demo_sensor_13",
    "green": 126,
    "icon": "mdi:fridge",
    "location": "frigo",
    "red": 42,
    "title": "Fridge"
   },
   {
    "blue": 176,
    "entityId": "sensor.demo_sensor_14",
    "green": 103,
    "icon": "mdi:snowflake",
    "location": "freezer",
    "red": 52,
    "title": "Freezer"
   },
   {
    "blue": 56,
    "entityId": "sensor.demo_kitchen_1",
    "green": 98,
    "icon": "mdi:shaker-outline",
    "location": "spice_rack",
    "red": 183,
    "title": "Spice Rack"
   },
   {
    "blue": 72,
    "entityId": "sensor.demo_kitchen_2",
    "green": 96,
    "icon": "mdi:cupboard",
    "location": "cabinet",
    "red": 118,
    "title": "Cabinet"
   }
  ],
  "totalItemsEntityId": "sensor.demo_sensor_15"
 },
 "home": {
  "airQualityEntityId": "sensor.demo_air_quality_1",
  "cameras": [
   {
    "aspectRatio": 1.3333333333333333,
    "entityId": "camera.demo_front_door_camera_item_1",
    "recordingEntityId": "input_boolean.demo_front_door_recording_1",
    "recordingScriptEntityId": "script.demo_front_door_recording_1",
    "rtcStreamId": "front_door",
    "title": "Front Door"
   },
   {
    "aspectRatio": 3.3333333333333335,
    "entityId": "camera.demo_garage_camera_item_1",
    "recordingEntityId": "input_boolean.demo_driveway_recording_1",
    "recordingScriptEntityId": "script.demo_driveway_recording_1",
    "rtcStreamId": "garage_camera",
    "title": "Driveway"
   },
   {
    "aspectRatio": 1.7777777777777777,
    "entityId": "camera.demo_upper_deck_camera_1",
    "recordingEntityId": "input_boolean.demo_upper_deck_recording_1",
    "recordingScriptEntityId": "script.demo_upper_deck_recording_1",
    "rtcStreamId": "upper_deck",
    "title": "Upper Deck"
   },
   {
    "aspectRatio": 1.7777777777777777,
    "entityId": "camera.demo_lower_deck_camera_item_1",
    "recordingEntityId": "input_boolean.demo_lower_deck_recording_1",
    "recordingScriptEntityId": "script.demo_lower_deck_recording_1",
    "rtcStreamId": "lower_deck",
    "title": "Lower Deck"
   }
  ],
  "guestToggles": [
   {
    "entityId": "input_boolean.demo_guest_room_1",
    "icon": "mdi:bed",
    "title": "Guest Room"
   },
   {
    "entityId": "input_boolean.demo_studio_1",
    "icon": "mdi:guitar-electric",
    "title": "Studio"
   },
   {
    "entityId": "input_boolean.demo_media_room_1",
    "icon": "mdi:projector",
    "title": "Media room"
   }
  ],
  "statusChips": [
   {
    "entityId": "light.demo_light_1",
    "icon": "mdi:lightbulb-group",
    "sheet": "lights",
    "title": "Lights",
    "tone": "light"
   },
   {
    "entityId": "alarm_control_panel.demo_alarm_control_panel_1",
    "icon": "mdi:shield-outline",
    "sheet": "security",
    "title": "Security",
    "tone": "security"
   },
   {
    "colorEntityId": "input_text.demo_color_1",
    "entityId": "input_text.demo_input_text_1",
    "icon": "mdi:thermometer",
    "sheet": "climate",
    "title": "Climate",
    "tone": "climate"
   },
   {
    "entityId": "binary_sensor.demo_binary_sensor_5",
    "icon": "mdi:motion-sensor",
    "sheet": "occupancy",
    "title": "Occupancy",
    "tone": "presence"
   },
   {
    "entityId": "binary_sensor.demo_contact_2",
    "icon": "mdi:door",
    "sheet": "contacts",
    "title": "Contact Sensors",
    "tone": "contact"
   },
   {
    "colorEntityId": "input_text.demo_color_2",
    "detailEntityId": "input_text.demo_pm25_range_1",
    "entityId": "input_text.demo_input_text_2",
    "icon": "mdi:blur",
    "sheet": "airQuality",
    "title": "Air Quality",
    "tone": "air"
   }
  ],
  "sunEntityId": "sun.demo_sun_1",
  "weatherEntityId": "weather.demo_weather_1"
 },
 "household": {
  "highAqiTile": {
   "entityId": "input_boolean.demo_mode_1",
   "icon": "mdi:air-purifier",
   "showsState": true,
   "title": "High AQI Mode"
  },
  "powerRecoveryAutomation": "automation.demo_living_room_power_1",
  "presenceRooms": [
   {
    "autoReenableEntityId": "switch.demo_living_room_presence_1",
    "presenceEntityId": "switch.demo_living_room_presence_2",
    "title": "Living Room"
   },
   {
    "autoReenableEntityId": "switch.demo_kitchen_presence_1",
    "presenceEntityId": "switch.demo_kitchen_presence_2",
    "title": "Kitchen"
   },
   {
    "autoReenableEntityId": "switch.demo_hallway_presence_1",
    "presenceEntityId": "switch.demo_hallway_presence_2",
    "title": "Hallway"
   },
   {
    "autoReenableEntityId": "switch.demo_gym_presence_1",
    "presenceEntityId": "switch.demo_gym_presence_2",
    "title": "Gym"
   },
   {
    "autoReenableEntityId": "switch.demo_presence_1",
    "presenceEntityId": "switch.demo_presence_2",
    "title": "Guest Bathroom"
   },
   {
    "autoReenableEntityId": "switch.demo_guest_room_presence_1",
    "presenceEntityId": "switch.demo_guest_room_presence_2",
    "title": "Guest Room"
   },
   {
    "autoReenableEntityId": "switch.demo_office_presence_1",
    "presenceEntityId": "switch.demo_office_presence_2",
    "title": "Office"
   },
   {
    "autoReenableEntityId": "switch.demo_bedroom_1_presence_1",
    "presenceEntityId": "switch.demo_bedroom_1_presence_2",
    "title": "Bedroom 1"
   },
   {
    "autoReenableEntityId": "switch.demo_bathroom_1_presence_1",
    "presenceEntityId": "switch.demo_bathroom_1_presence_2",
    "title": "Bathroom 1"
   },
   {
    "autoReenableEntityId": "switch.demo_dining_room_presence_1",
    "presenceEntityId": "switch.demo_dining_room_presence_2",
    "title": "Dining Room"
   },
   {
    "autoReenableEntityId": "switch.demo_media_room_presence_1",
    "presenceEntityId": "switch.demo_media_room_presence_2",
    "title": "Media room"
   },
   {
    "autoReenableEntityId": "switch.demo_downstairs_hallway_presence_1",
    "presenceEntityId": "switch.demo_downstairs_hallway_presence_2",
    "title": "Downstairs Hallway"
   },
   {
    "autoReenableEntityId": "switch.demo_studio_presence_1",
    "presenceEntityId": "switch.demo_studio_presence_2",
    "title": "Studio"
   },
   {
    "autoReenableEntityId": "switch.demo_upper_deck_presence_1",
    "presenceEntityId": "switch.demo_back_deck_presence_1",
    "title": "Upper Deck"
   }
  ],
  "relayControlEntityId": "input_boolean.demo_mode_2",
  "relayTiles": [
   {
    "entityId": "input_boolean.demo_mode_2",
    "icon": "mdi:toggle-switch",
    "showsState": true,
    "title": "Relay Control Mode"
   }
  ],
  "securityTiles": [
   {
    "entityId": "input_boolean.demo_front_door_lock_1",
    "icon": "mdi:lock-clock",
    "showsState": true,
    "title": "Front Door Auto-Lock"
   }
  ],
  "showSpecificTiles": [
   {
    "entityId": "input_boolean.demo_input_boolean_3",
    "icon": "mdi:water",
    "showsState": true,
    "title": "Outdoor Faucets"
   },
   {
    "entityId": "input_boolean.demo_input_boolean_4",
    "icon": "mdi:string-lights",
    "showsState": true,
    "title": "Holiday Lights"
   }
  ],
  "vehicleTiles": [
   {
    "entityId": "sensor.demo_sensor_16",
    "icon": "mdi:ev-station",
    "showsState": true,
    "title": "Charge Status"
   },
   {
    "entityId": "lock.demo_lock_1",
    "icon": "mdi:car-door-lock",
    "showsState": true,
    "title": "Doors"
   },
   {
    "entityId": "select.demo_select_1",
    "icon": "mdi:car-seat",
    "showsState": true,
    "title": "Driver's Seat"
   },
   {
    "entityId": "select.demo_select_2",
    "icon": "mdi:car-seat",
    "showsState": true,
    "title": "Passenger Seat"
   },
   {
    "entityId": "number.demo_number_1",
    "icon": "mdi:car-defrost-front",
    "showsState": true,
    "title": "Climate"
   }
  ]
 },
 "media": {
  "pageSections": [
   {
    "cards": [
     {
      "device": {
       "activeHoldResetEntityIds": [],
       "activeStates": [
        "on",
        "playing"
       ],
       "entityId": "media_player.demo_living_room_1",
       "icon": "mdi:television",
       "semantics": {
        "type": "state"
       },
       "stateLabels": {},
       "title": "Living Room STREAMER"
      },
      "isFullWidth": true,
      "offIcon": "mdi:television-off",
      "remoteId": "living-room-streamer",
      "section": "Living Room"
     }
    ],
    "title": "Living Room"
   },
   {
    "cards": [
     {
      "device": {
       "activeHoldResetEntityIds": [],
       "activeStates": [],
       "entityId": "media_player.demo_studio_1",
       "icon": "mdi:remote",
       "semantics": {
        "type": "state"
       },
       "stateLabels": {},
       "title": "Studio Remote"
      },
      "isFullWidth": true,
      "remoteId": "studio-remote",
      "section": "Studio"
     },
     {
      "device": {
       "action": {
        "cases": [
         {
          "command": {
           "call": {
            "data": {},
            "domain": "script",
            "service": "demo_studio_tv_off"
           },
           "optimistic": [
            {
             "entityId": "media_player.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "sensor.demo_studio_source_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "Off"
            },
            {
             "entityId": "media_player.demo_media_player_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "switch.demo_studio_power_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "switch.demo_studio_light_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            }
           ],
           "type": "service"
          },
          "states": [
           "Game Console",
           "Game"
          ]
         }
        ],
        "entityId": "sensor.demo_studio_source_1",
        "otherwise": {
         "call": {
          "data": {},
          "domain": "script",
          "service": "demo_studio_console"
         },
         "optimistic": [
          {
           "entityId": "media_player.demo_media_player_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 90,
           "value": "on"
          },
          {
           "entityId": "media_player.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 90,
           "value": "on"
          },
          {
           "entityId": "sensor.demo_studio_source_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 90,
           "value": "Game Console"
          },
          {
           "entityId": "switch.demo_studio_power_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 90,
           "value": "on"
          },
          {
           "entityId": "switch.demo_studio_light_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 90,
           "value": "off"
          },
          {
           "entityId": "select.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 90,
           "value": "HDMI 1"
          }
         ],
         "type": "service"
        },
        "type": "state"
       },
       "activeHoldResetEntityIds": [],
       "activeStates": [
        "Game Console",
        "Game"
       ],
       "entityId": "sensor.demo_studio_source_1",
       "icon": "mdi:gamepad",
       "semantics": {
        "states": [
         "Game Console",
         "Game"
        ],
        "type": "selectedWhen"
       },
       "stateLabels": {
        "Computer": "Off",
        "Game": "On",
        "Game Console": "On",
        "Off": "Off",
        "Server": "Off",
        "TV": "Off"
       },
       "title": "Game Console"
      },
      "isFullWidth": false,
      "section": "Studio"
     },
     {
      "device": {
       "action": {
        "cases": [
         {
          "command": {
           "call": {
            "data": {},
            "domain": "script",
            "service": "demo_studio_tv_off"
           },
           "optimistic": [
            {
             "entityId": "media_player.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "sensor.demo_studio_source_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "Off"
            },
            {
             "entityId": "media_player.demo_media_player_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "switch.demo_studio_power_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "switch.demo_studio_light_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            }
           ],
           "type": "service"
          },
          "states": [
           "Server"
          ]
         }
        ],
        "entityId": "sensor.demo_studio_source_1",
        "otherwise": {
         "call": {
          "data": {},
          "domain": "script",
          "service": "demo_studio_server"
         },
         "optimistic": [
          {
           "entityId": "media_player.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "on"
          },
          {
           "entityId": "sensor.demo_studio_source_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "Server"
          },
          {
           "entityId": "switch.demo_studio_power_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "on"
          },
          {
           "entityId": "switch.demo_studio_light_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "off"
          },
          {
           "entityId": "select.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "HDMI 2"
          }
         ],
         "type": "service"
        },
        "type": "state"
       },
       "activeHoldResetEntityIds": [],
       "activeStates": [
        "Server"
       ],
       "entityId": "sensor.demo_studio_source_1",
       "icon": "mdi:server",
       "semantics": {
        "states": [
         "Server"
        ],
        "type": "selectedWhen"
       },
       "stateLabels": {
        "Computer": "Off",
        "Game": "Off",
        "Game Console": "Off",
        "Off": "Off",
        "Server": "On",
        "TV": "Off"
       },
       "title": "Server"
      },
      "isFullWidth": false,
      "section": "Studio"
     },
     {
      "device": {
       "action": {
        "cases": [
         {
          "command": {
           "call": {
            "data": {},
            "domain": "script",
            "service": "demo_studio_tv_off"
           },
           "optimistic": [
            {
             "entityId": "media_player.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "sensor.demo_studio_source_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "Off"
            },
            {
             "entityId": "media_player.demo_media_player_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "switch.demo_studio_power_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            },
            {
             "entityId": "switch.demo_studio_light_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 180,
             "value": "off"
            }
           ],
           "type": "service"
          },
          "states": [
           "Computer"
          ]
         }
        ],
        "entityId": "sensor.demo_studio_source_1",
        "otherwise": {
         "call": {
          "data": {},
          "domain": "script",
          "service": "demo_studio_windows_pc"
         },
         "optimistic": [
          {
           "entityId": "media_player.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "on"
          },
          {
           "entityId": "sensor.demo_studio_source_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "Computer"
          },
          {
           "entityId": "switch.demo_studio_power_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "on"
          },
          {
           "entityId": "switch.demo_studio_light_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "off"
          },
          {
           "entityId": "select.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "HDMI 3"
          }
         ],
         "type": "service"
        },
        "type": "state"
       },
       "activeHoldResetEntityIds": [],
       "activeStates": [
        "Computer"
       ],
       "entityId": "sensor.demo_studio_source_1",
       "icon": "mdi:desktop-classic",
       "semantics": {
        "states": [
         "Computer"
        ],
        "type": "selectedWhen"
       },
       "stateLabels": {
        "Computer": "On",
        "Game": "Off",
        "Game Console": "Off",
        "Off": "Off",
        "Server": "Off",
        "TV": "Off"
       },
       "title": "Computer"
      },
      "isFullWidth": false,
      "section": "Studio"
     },
     {
      "device": {
       "action": {
        "command": {
         "call": {
          "data": {},
          "domain": "script",
          "service": "demo_studio_game"
         },
         "optimistic": [
          {
           "entityId": "media_player.demo_media_player_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 120,
           "value": "on"
          },
          {
           "entityId": "media_player.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 120,
           "value": "on"
          },
          {
           "entityId": "sensor.demo_studio_source_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 120,
           "value": "Game"
          },
          {
           "entityId": "switch.demo_studio_power_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 120,
           "value": "on"
          },
          {
           "entityId": "switch.demo_studio_light_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 120,
           "value": "on"
          },
          {
           "entityId": "select.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 120,
           "value": "HDMI 1"
          }
         ],
         "type": "service"
        },
        "type": "command"
       },
       "activeHoldResetEntityIds": [],
       "activeStates": [
        "Game"
       ],
       "entityId": "sensor.demo_studio_source_1",
       "icon": "mdi:gamepad-variant",
       "semantics": {
        "states": [
         "Game"
        ],
        "type": "selectedWhen"
       },
       "stateLabels": {
        "Computer": "Off",
        "Game": "On",
        "Game Console": "Off",
        "Off": "Off",
        "Server": "Off",
        "TV": "Off"
       },
       "title": "Game"
      },
      "isFullWidth": false,
      "section": "Studio"
     }
    ],
    "title": "Studio"
   },
   {
    "cards": [
     {
      "device": {
       "activeHoldResetEntityIds": [],
       "activeStates": [
        "on",
        "playing"
       ],
       "entityId": "media_player.demo_media_player_2",
       "icon": "mdi:projector",
       "semantics": {
        "type": "state"
       },
       "stateLabels": {},
       "title": "Media room"
      },
      "isFullWidth": true,
      "remoteId": "media-room-streamer",
      "section": "Media room"
     },
     {
      "device": {
       "action": {
        "command": {
         "call": {
          "data": {},
          "domain": "script",
          "service": "demo_media_room_handheld_switch"
         },
         "optimistic": [],
         "type": "service"
        },
        "type": "command"
       },
       "activeHoldResetEntityIds": [],
       "activeStates": [
        "on",
        "playing"
       ],
       "entityId": "input_boolean.demo_switch_1",
       "icon": "mdi:gamepad-round",
       "semantics": {
        "states": [
         "on",
         "playing"
        ],
        "type": "toggleOnWhen"
       },
       "stateLabels": {},
       "title": "Handheld Console"
      },
      "isFullWidth": false,
      "section": "Media room"
     },
     {
      "device": {
       "action": {
        "command": {
         "call": {
          "data": {},
          "domain": "script",
          "service": "demo_media_room_tv_movie"
         },
         "optimistic": [],
         "type": "service"
        },
        "type": "command"
       },
       "activeHoldResetEntityIds": [],
       "activeStates": [
        "on",
        "playing"
       ],
       "entityId": "input_boolean.demo_input_boolean_5",
       "icon": "mdi:television",
       "semantics": {
        "states": [
         "on",
         "playing"
        ],
        "type": "toggleOnWhen"
       },
       "stateLabels": {},
       "title": "Media STREAMER"
      },
      "isFullWidth": false,
      "section": "Media room"
     }
    ],
    "title": "Media room"
   }
  ],
  "remoteIdByMediaPlayer": {
   "media_player.demo_living_room_1": "living-room-streamer",
   "media_player.demo_living_room_2": "living-room-streamer",
   "media_player.demo_media_player_2": "media-room-streamer",
   "media_player.demo_media_room_1": "media-room-streamer",
   "media_player.demo_studio_1": "studio-remote"
  },
  "remotes": [
   {
    "appSectionTitle": "Media",
    "apps": [
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.streamapp.player",
          "entity": "media_player.demo_living_room_1",
          "remote_entity": "remote.demo_living_room_1"
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streama.png",
      "title": "Streaming A",
      "whiteBackground": false
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.demo.player.streamb.tv",
          "entity": "media_player.demo_living_room_1",
          "remote_entity": "remote.demo_living_room_1"
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streamb.png",
      "title": "Streaming B",
      "whiteBackground": true
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.streamc.demo",
          "entity": "media_player.demo_living_room_1",
          "remote_entity": "remote.demo_living_room_1"
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streamc.png",
      "title": "Streaming C",
      "whiteBackground": false
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.shop.streamd.livingroom",
          "entity": "media_player.demo_living_room_1",
          "remote_entity": "remote.demo_living_room_1"
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streamd.jpeg",
      "title": "Streaming D",
      "whiteBackground": false
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.streame.player",
          "entity": "media_player.demo_living_room_1",
          "remote_entity": "remote.demo_living_room_1"
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streame.png",
      "title": "Streaming E",
      "whiteBackground": false
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.streamf.streamf",
          "entity": "media_player.demo_living_room_1",
          "remote_entity": "remote.demo_living_room_1"
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streamf.png",
      "title": "Streaming F",
      "whiteBackground": false
     }
    ],
    "back": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "BACK"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:triangle-down",
     "iconRotationDegrees": 90,
     "label": "Back"
    },
    "controlEntityId": "media_player.demo_living_room_2",
    "devices": [],
    "down": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_DOWN"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-down",
     "iconRotationDegrees": 0,
     "label": "Down"
    },
    "hideKeyboardWhenOff": false,
    "home": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "HOME"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:circle",
     "iconRotationDegrees": 0,
     "label": "Home"
    },
    "id": "living-room-streamer",
    "keyboard": {
     "action": {
      "command": {
       "targetEntityId": "media_player.demo_living_room_2",
       "type": "textPrompt"
      },
      "type": "command"
     },
     "icon": "mdi:keyboard",
     "iconRotationDegrees": 0,
     "label": "Keyboard"
    },
    "left": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_LEFT"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-left",
     "iconRotationDegrees": 0,
     "label": "Left"
    },
    "liveChangeEntityIds": [],
    "mediaEntityId": "media_player.demo_living_room_2",
    "optimisticEntityIds": [],
    "pause": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "MEDIA_PAUSE"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:pause",
     "iconRotationDegrees": 0,
     "label": "Pause"
    },
    "play": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "MEDIA_PLAY"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:play",
     "iconRotationDegrees": 0,
     "label": "Play"
    },
    "power": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "POWER"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:power",
     "iconColorRule": {
      "entityIds": [
       "media_player.demo_living_room_2"
      ],
      "inactiveStates": [
       "off",
       "unavailable",
       "unknown"
      ],
      "inactiveStatesByEntity": {}
     },
     "iconRotationDegrees": 0,
     "label": "Power"
    },
    "remoteTitle": "Living Room STREAMER Remote",
    "right": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_RIGHT"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-right",
     "iconRotationDegrees": 0,
     "label": "Right"
    },
    "roomTitle": "Living Room",
    "select": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_CENTER"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": " ",
     "iconRotationDegrees": 0,
     "label": "Select"
    },
    "showVolumeWhenOff": false,
    "title": "Living Room STREAMER",
    "up": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_UP"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_living_room_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-up",
     "iconRotationDegrees": 0,
     "label": "Up"
    },
    "volumeDown": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "media_player",
        "service": "demo_volume_down",
        "target": "media_player.demo_media_player_3"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-minus",
     "iconRotationDegrees": 0,
     "label": "Volume Down"
    },
    "volumeEntityId": "media_player.demo_media_player_3",
    "volumeMute": {
     "action": {
      "command": {
       "call": {
        "data": {
         "speakerdevice": [
          "media_player.demo_media_player_3"
         ]
        },
        "domain": "script",
        "service": "demo_toggle_speaker_mute"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-mute",
     "iconRotationDegrees": 0,
     "label": "Mute"
    },
    "volumeTitle": "Speaker Volume",
    "volumeUp": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "media_player",
        "service": "demo_volume_up",
        "target": "media_player.demo_media_player_3"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-plus",
     "iconRotationDegrees": 0,
     "label": "Volume Up"
    }
   },
   {
    "appSectionTitle": "Media",
    "apps": [
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_name": "Streaming A",
          "entity": "media_player.demo_bedroom_1_1",
          "remote_entity": "remote.demo_bedroom_1_1"
         },
         "domain": "script",
         "service": "demo_launch_app_on_streamer_tv"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streama.png",
      "title": "Streaming A",
      "whiteBackground": false
     }
    ],
    "back": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "menu"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-left",
     "iconRotationDegrees": 0,
     "label": "Menu"
    },
    "controlEntityId": "media_player.demo_bedroom_1_1",
    "devices": [],
    "down": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "down"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-down",
     "iconRotationDegrees": 0,
     "label": "Down"
    },
    "hideKeyboardWhenOff": false,
    "home": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "home"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:home",
     "iconRotationDegrees": 0,
     "label": "Home"
    },
    "id": "bedroom-1-streamer-tv",
    "left": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "left"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-left",
     "iconRotationDegrees": 0,
     "label": "Left"
    },
    "liveChangeEntityIds": [],
    "mediaEntityId": "media_player.demo_bedroom_1_1",
    "optimisticEntityIds": [],
    "pause": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "pause"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:pause",
     "iconRotationDegrees": 0,
     "label": "Pause"
    },
    "play": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "play"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:play",
     "iconRotationDegrees": 0,
     "label": "Play"
    },
    "power": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "script",
        "service": "demo_streamer_tv_power_on_off"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:power",
     "iconColorRule": {
      "entityIds": [
       "media_player.demo_bedroom_1_1"
      ],
      "inactiveStates": [
       "off",
       "standby",
       "unavailable"
      ],
      "inactiveStatesByEntity": {}
     },
     "iconRotationDegrees": 0,
     "label": "Power"
    },
    "remoteTitle": "Streamer Remote",
    "right": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "right"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-right",
     "iconRotationDegrees": 0,
     "label": "Right"
    },
    "roomTitle": "Bedroom 1",
    "select": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "select"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:circle",
     "iconRotationDegrees": 0,
     "label": "Select"
    },
    "showVolumeWhenOff": false,
    "title": "Streamer",
    "up": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "up"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_bedroom_1_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-up",
     "iconRotationDegrees": 0,
     "label": "Up"
    },
    "volumeDown": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "media_player",
        "service": "demo_volume_down",
        "target": "media_player.demo_media_player_4"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-minus",
     "iconRotationDegrees": 0,
     "label": "Volume Down"
    },
    "volumeEntityId": "media_player.demo_media_player_4",
    "volumeMute": {
     "action": {
      "command": {
       "call": {
        "data": {
         "speakerdevice": [
          "media_player.demo_media_player_4"
         ]
        },
        "domain": "script",
        "service": "demo_toggle_speaker_mute"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-mute",
     "iconRotationDegrees": 0,
     "label": "Mute"
    },
    "volumeTitle": "Volume",
    "volumeUp": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "media_player",
        "service": "demo_volume_up",
        "target": "media_player.demo_media_player_4"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-plus",
     "iconRotationDegrees": 0,
     "label": "Volume Up"
    }
   },
   {
    "appSectionTitle": "Media",
    "apps": [
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.streamapp.player",
          "entity": "media_player.demo_media_room_1",
          "remote_entity": "remote.demo_remote_1",
          "turn_on_projector": true
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streama.png",
      "title": "Streaming A",
      "whiteBackground": false
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.demo.player.streamb.tv",
          "entity": "media_player.demo_media_room_1",
          "remote_entity": "remote.demo_remote_1",
          "turn_on_projector": true
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streamb.png",
      "title": "Streaming B",
      "whiteBackground": true
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.streamc.demo",
          "entity": "media_player.demo_media_room_1",
          "remote_entity": "remote.demo_remote_1",
          "turn_on_projector": true
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streamc.png",
      "title": "Streaming C",
      "whiteBackground": false
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.shop.streamd.livingroom",
          "entity": "media_player.demo_media_room_1",
          "remote_entity": "remote.demo_remote_1",
          "turn_on_projector": true
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streamd.jpeg",
      "title": "Streaming D",
      "whiteBackground": false
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.streame.player",
          "entity": "media_player.demo_media_room_1",
          "remote_entity": "remote.demo_remote_1",
          "turn_on_projector": true
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streame.png",
      "title": "Streaming E",
      "whiteBackground": false
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {
          "app_id": "com.streamf.streamf",
          "entity": "media_player.demo_media_room_1",
          "remote_entity": "remote.demo_remote_1",
          "turn_on_projector": true
         },
         "domain": "script",
         "service": "demo_launch_app_on_media_player"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [],
      "imagePath": "/local/images/apps/streamf.png",
      "title": "Streaming F",
      "whiteBackground": false
     }
    ],
    "back": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "BACK"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:triangle-down",
     "iconRotationDegrees": 90,
     "label": "Back"
    },
    "controlEntityId": "media_player.demo_media_room_1",
    "devices": [
     {
      "action": {
       "command": {
        "call": {
         "data": {},
         "domain": "media_player",
         "service": "demo_toggle",
         "target": "media_player.demo_media_player_2"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeHoldResetEntityIds": [],
      "activeStates": [],
      "entityId": "media_player.demo_media_player_2",
      "icon": "mdi:projector",
      "stateLabels": {},
      "title": "Projector"
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {},
         "domain": "media_player",
         "service": "demo_toggle",
         "target": "media_player.demo_media_player_5"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeHoldResetEntityIds": [],
      "activeStates": [],
      "entityId": "media_player.demo_media_player_5",
      "icon": "mdi:audio-video",
      "stateLabels": {},
      "title": "Receiver"
     },
     {
      "action": {
       "command": {
        "call": {
         "data": {},
         "domain": "media_player",
         "service": "demo_toggle",
         "target": "media_player.demo_media_room_1"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "command"
      },
      "activeHoldResetEntityIds": [],
      "activeStates": [],
      "entityId": "media_player.demo_media_room_1",
      "icon": "mdi:remote-tv",
      "stateLabels": {},
      "title": "Media room STREAMER"
     },
     {
      "action": {
       "cases": [
        {
         "command": {
          "call": {
           "data": {},
           "domain": "input_button",
           "service": "demo_press",
           "target": "input_button.demo_input_button_5"
          },
          "optimistic": [],
          "type": "service"
         },
         "states": [
          "on"
         ]
        }
       ],
       "otherwise": {
        "call": {
         "data": {},
         "domain": "input_button",
         "service": "demo_press",
         "target": "input_button.demo_input_button_6"
        },
        "optimistic": [],
        "type": "service"
       },
       "type": "state"
      },
      "activeHoldResetEntityIds": [],
      "activeStates": [],
      "entityId": "input_boolean.demo_power_1",
      "icon": "mdi:projector",
      "stateLabels": {},
      "title": "Media Room Computer"
     }
    ],
    "down": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_DOWN"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-down",
     "iconRotationDegrees": 0,
     "label": "Down"
    },
    "hideKeyboardWhenOff": false,
    "home": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "HOME"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:circle",
     "iconRotationDegrees": 0,
     "label": "Home"
    },
    "id": "media-room-streamer",
    "keyboard": {
     "action": {
      "command": {
       "targetEntityId": "media_player.demo_media_room_1",
       "type": "textPrompt"
      },
      "type": "command"
     },
     "icon": "mdi:keyboard",
     "iconRotationDegrees": 0,
     "label": "Keyboard"
    },
    "left": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_LEFT"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-left",
     "iconRotationDegrees": 0,
     "label": "Left"
    },
    "liveChangeEntityIds": [],
    "mediaEntityId": "media_player.demo_media_room_1",
    "optimisticEntityIds": [],
    "pause": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "MEDIA_PAUSE"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:pause",
     "iconRotationDegrees": 0,
     "label": "Pause"
    },
    "play": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "MEDIA_PLAY"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:play",
     "iconRotationDegrees": 0,
     "label": "Play"
    },
    "power": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "script",
        "service": "demo_room_power_toggle"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:power",
     "iconColorRule": {
      "entityIds": [
       "media_player.demo_media_room_1"
      ],
      "inactiveStates": [
       "off",
       "unavailable",
       "unknown"
      ],
      "inactiveStatesByEntity": {}
     },
     "iconRotationDegrees": 0,
     "label": "Power"
    },
    "remoteTitle": "Media room STREAMER Remote",
    "right": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_RIGHT"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-right",
     "iconRotationDegrees": 0,
     "label": "Right"
    },
    "roomTitle": "Media room",
    "select": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_CENTER"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": " ",
     "iconRotationDegrees": 0,
     "label": "Select"
    },
    "showVolumeWhenOff": true,
    "title": "Media room STREAMER",
    "up": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_UP"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_remote_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-up",
     "iconRotationDegrees": 0,
     "label": "Up"
    },
    "volumeDown": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "media_player",
        "service": "demo_volume_down",
        "target": "media_player.demo_media_player_5"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-minus",
     "iconRotationDegrees": 0,
     "label": "Volume Down"
    },
    "volumeEntityId": "media_player.demo_media_player_5",
    "volumeMute": {
     "action": {
      "command": {
       "call": {
        "data": {
         "is_volume_muted": true
        },
        "domain": "media_player",
        "service": "demo_volume_mute",
        "target": "media_player.demo_media_player_5"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-mute",
     "iconRotationDegrees": 0,
     "label": "Mute"
    },
    "volumeTitle": "Receiver Volume",
    "volumeUp": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "media_player",
        "service": "demo_volume_up",
        "target": "media_player.demo_media_player_5"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-plus",
     "iconRotationDegrees": 0,
     "label": "Volume Up"
    }
   },
   {
    "appSectionTitle": "Quick App Launch",
    "apps": [
     {
      "action": {
       "command": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_game"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_media_player_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 120,
          "value": "on"
         },
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 120,
          "value": "on"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 120,
          "value": "Game"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 120,
          "value": "on"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 120,
          "value": "on"
         },
         {
          "entityId": "select.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 120,
          "value": "HDMI 1"
         }
        ],
        "type": "service"
       },
       "type": "command"
      },
      "activeStates": [
       "Game"
      ],
      "icon": "mdi:gamepad-variant",
      "semantics": {
       "states": [
        "Game"
       ],
       "type": "selectedWhen"
      },
      "stateEntityId": "sensor.demo_studio_source_1",
      "title": "Game",
      "whiteBackground": false
     }
    ],
    "back": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "BACK"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:triangle-down",
     "iconRotationDegrees": 90,
     "label": "Back"
    },
    "controlEntityId": "media_player.demo_studio_1",
    "devices": [
     {
      "action": {
       "cases": [
        {
         "command": {
          "call": {
           "data": {},
           "domain": "script",
           "service": "demo_studio_tv"
          },
          "optimistic": [
           {
            "entityId": "media_player.demo_studio_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 20,
            "value": "on"
           },
           {
            "entityId": "sensor.demo_studio_source_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 20,
            "value": "TV"
           },
           {
            "entityId": "switch.demo_studio_power_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 20,
            "value": "on"
           },
           {
            "entityId": "switch.demo_studio_light_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 20,
            "value": "off"
           }
          ],
          "type": "service"
         },
         "states": [
          "off",
          "unavailable",
          "unknown"
         ]
        }
       ],
       "entityId": "media_player.demo_studio_1",
       "otherwise": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_tv_off"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "Off"
         },
         {
          "entityId": "media_player.demo_media_player_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         }
        ],
        "type": "service"
       },
       "type": "state"
      },
      "activeHoldResetEntityIds": [],
      "activeStates": [],
      "entityId": "media_player.demo_studio_1",
      "icon": "mdi:television",
      "semantics": {
       "states": [
        "off",
        "unavailable",
        "unknown"
       ],
       "type": "toggleOnUnless"
      },
      "stateLabels": {},
      "title": "TV"
     },
     {
      "action": {
       "cases": [
        {
         "command": {
          "call": {
           "data": {},
           "domain": "script",
           "service": "demo_studio_console_off"
          },
          "optimistic": [
           {
            "entityId": "media_player.demo_media_player_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           },
           {
            "entityId": "sensor.demo_studio_status_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "plugged"
           }
          ],
          "type": "service"
         },
         "states": [
          "on",
          "playing",
          "paused",
          "linked"
         ]
        }
       ],
       "entityId": "media_player.demo_media_player_1",
       "otherwise": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_console"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_media_player_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 90,
          "value": "on"
         },
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 90,
          "value": "on"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 90,
          "value": "Game Console"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 90,
          "value": "on"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 90,
          "value": "off"
         },
         {
          "entityId": "select.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 90,
          "value": "HDMI 1"
         }
        ],
        "type": "service"
       },
       "type": "state"
      },
      "activeHoldResetEntityIds": [
       "media_player.demo_studio_1",
       "switch.demo_studio_power_1",
       "select.demo_studio_1",
       "sensor.demo_studio_source_1"
      ],
      "activeHoldSeconds": 45,
      "activeStates": [
       "on"
      ],
      "entityId": "media_player.demo_media_player_1",
      "icon": "mdi:gamepad",
      "semantics": {
       "states": [
        "on",
        "playing",
        "paused"
       ],
       "type": "toggleOnWhen"
      },
      "stateEntityIds": [
       "media_player.demo_media_player_1",
       "sensor.demo_studio_status_1",
       "media_player.demo_studio_1",
       "switch.demo_studio_power_1",
       "select.demo_studio_1"
      ],
      "stateLabels": {},
      "stateResolver": {
       "consoleState": {}
      },
      "title": "Game Console"
     },
     {
      "action": {
       "cases": [
        {
         "command": {
          "call": {
           "data": {},
           "domain": "script",
           "service": "demo_studio_tv_off"
          },
          "optimistic": [
           {
            "entityId": "media_player.demo_studio_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           },
           {
            "entityId": "sensor.demo_studio_source_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "Off"
           },
           {
            "entityId": "media_player.demo_media_player_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           },
           {
            "entityId": "switch.demo_studio_power_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           },
           {
            "entityId": "switch.demo_studio_light_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           }
          ],
          "type": "service"
         },
         "states": [
          "Server"
         ]
        }
       ],
       "entityId": "sensor.demo_studio_source_1",
       "otherwise": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_server"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "on"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "Server"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "on"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "off"
         },
         {
          "entityId": "select.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "HDMI 2"
         }
        ],
        "type": "service"
       },
       "type": "state"
      },
      "activeHoldResetEntityIds": [],
      "activeStates": [
       "Server"
      ],
      "entityId": "sensor.demo_studio_source_1",
      "icon": "mdi:server",
      "semantics": {
       "states": [
        "Server"
       ],
       "type": "selectedWhen"
      },
      "stateLabels": {
       "Computer": "Off",
       "Game": "Off",
       "Game Console": "Off",
       "Off": "Off",
       "Server": "On",
       "TV": "Off"
      },
      "title": "Server"
     },
     {
      "action": {
       "cases": [
        {
         "command": {
          "call": {
           "data": {},
           "domain": "script",
           "service": "demo_studio_tv_off"
          },
          "optimistic": [
           {
            "entityId": "media_player.demo_studio_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           },
           {
            "entityId": "sensor.demo_studio_source_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "Off"
           },
           {
            "entityId": "media_player.demo_media_player_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           },
           {
            "entityId": "switch.demo_studio_power_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           },
           {
            "entityId": "switch.demo_studio_light_1",
            "failsOnTimeout": false,
            "revertAfterSeconds": 180,
            "value": "off"
           }
          ],
          "type": "service"
         },
         "states": [
          "Computer"
         ]
        }
       ],
       "entityId": "sensor.demo_studio_source_1",
       "otherwise": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_windows_pc"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "on"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "Computer"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "on"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "off"
         },
         {
          "entityId": "select.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "HDMI 3"
         }
        ],
        "type": "service"
       },
       "type": "state"
      },
      "activeHoldResetEntityIds": [],
      "activeStates": [
       "Computer"
      ],
      "entityId": "sensor.demo_studio_source_1",
      "icon": "mdi:desktop-classic",
      "semantics": {
       "states": [
        "Computer"
       ],
       "type": "selectedWhen"
      },
      "stateLabels": {
       "Computer": "On",
       "Game": "Off",
       "Game Console": "Off",
       "Off": "Off",
       "Server": "Off",
       "TV": "Off"
      },
      "title": "Computer"
     },
     {
      "activeHoldResetEntityIds": [],
      "activeStates": [],
      "entityId": "media_player.demo_media_player_6",
      "icon": "mdi:speaker",
      "semantics": {
       "type": "state"
      },
      "stateLabels": {},
      "title": "Soundbar"
     }
    ],
    "down": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_DOWN"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-down",
     "iconRotationDegrees": 0,
     "label": "Down"
    },
    "hideKeyboardWhenOff": false,
    "home": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "HOME"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:circle",
     "iconRotationDegrees": 0,
     "label": "Home"
    },
    "id": "studio-remote",
    "left": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_LEFT"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-left",
     "iconRotationDegrees": 0,
     "label": "Left"
    },
    "lightSync": {
     "brightnessEntityId": "number.demo_studio_brightness_1",
     "hdmiInputEntityId": "select.demo_studio_1",
     "hdmiStatusEntityIds": [
      "sensor.demo_studio_status_1",
      "sensor.demo_studio_status_2",
      "sensor.demo_studio_status_3",
      "sensor.demo_studio_status_4"
     ],
     "intensityEntityId": "select.demo_studio_2",
     "lightSyncEntityId": "switch.demo_studio_light_1",
     "powerEntityId": "switch.demo_studio_power_1",
     "syncModeEntityId": "select.demo_studio_mode_1"
    },
    "liveChangeEntityIds": [
     "sensor.demo_studio_source_1"
    ],
    "mediaEntityId": "media_player.demo_studio_1",
    "optimisticEntityIds": [
     "sensor.demo_studio_source_1",
     "media_player.demo_studio_1",
     "media_player.demo_media_player_1",
     "sensor.demo_studio_status_1",
     "switch.demo_studio_power_1",
     "switch.demo_studio_light_1",
     "select.demo_studio_1",
     "switch.demo_studio_power_1",
     "switch.demo_studio_light_1",
     "number.demo_studio_brightness_1",
     "select.demo_studio_1",
     "select.demo_studio_mode_1",
     "select.demo_studio_2"
    ],
    "pause": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "MEDIA_PAUSE"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:pause",
     "iconRotationDegrees": 0,
     "label": "Pause"
    },
    "play": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "MEDIA_PLAY"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:play",
     "iconRotationDegrees": 0,
     "label": "Play"
    },
    "power": {
     "action": {
      "cases": [
       {
        "command": {
         "call": {
          "data": {},
          "domain": "script",
          "service": "demo_studio_tv"
         },
         "optimistic": [
          {
           "entityId": "media_player.demo_studio_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "on"
          },
          {
           "entityId": "sensor.demo_studio_source_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "TV"
          },
          {
           "entityId": "switch.demo_studio_power_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "on"
          },
          {
           "entityId": "switch.demo_studio_light_1",
           "failsOnTimeout": false,
           "revertAfterSeconds": 20,
           "value": "off"
          }
         ],
         "type": "service"
        },
        "states": [
         "off",
         "unavailable",
         "unknown"
        ]
       }
      ],
      "entityId": "media_player.demo_studio_1",
      "otherwise": {
       "call": {
        "data": {},
        "domain": "script",
        "service": "demo_studio_tv_off"
       },
       "optimistic": [
        {
         "entityId": "media_player.demo_studio_1",
         "failsOnTimeout": false,
         "revertAfterSeconds": 180,
         "value": "off"
        },
        {
         "entityId": "sensor.demo_studio_source_1",
         "failsOnTimeout": false,
         "revertAfterSeconds": 180,
         "value": "Off"
        },
        {
         "entityId": "media_player.demo_media_player_1",
         "failsOnTimeout": false,
         "revertAfterSeconds": 180,
         "value": "off"
        },
        {
         "entityId": "switch.demo_studio_power_1",
         "failsOnTimeout": false,
         "revertAfterSeconds": 180,
         "value": "off"
        },
        {
         "entityId": "switch.demo_studio_light_1",
         "failsOnTimeout": false,
         "revertAfterSeconds": 180,
         "value": "off"
        }
       ],
       "type": "service"
      },
      "type": "state"
     },
     "icon": "mdi:power",
     "iconColorRule": {
      "entityIds": [
       "media_player.demo_studio_1"
      ],
      "inactiveStates": [
       "off",
       "unavailable",
       "unknown"
      ],
      "inactiveStatesByEntity": {}
     },
     "iconRotationDegrees": 0,
     "label": "Power",
     "semantics": {
      "states": [
       "off",
       "unavailable",
       "unknown"
      ],
      "type": "toggleOnUnless"
     }
    },
    "remoteTitle": "Studio Remote",
    "right": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_RIGHT"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-right",
     "iconRotationDegrees": 0,
     "label": "Right"
    },
    "roomTitle": "Studio",
    "select": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_CENTER"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": " ",
     "iconRotationDegrees": 0,
     "label": "Select"
    },
    "showVolumeWhenOff": true,
    "title": "Studio Remote",
    "up": {
     "action": {
      "command": {
       "call": {
        "data": {
         "command": "DPAD_UP"
        },
        "domain": "remote",
        "service": "demo_send_command",
        "target": "remote.demo_studio_1"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:chevron-up",
     "iconRotationDegrees": 0,
     "label": "Up"
    },
    "volumeDown": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "media_player",
        "service": "demo_volume_down",
        "target": "media_player.demo_media_player_6"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-minus",
     "iconRotationDegrees": 0,
     "label": "Volume Down"
    },
    "volumeEntityId": "media_player.demo_media_player_6",
    "volumeMute": {
     "action": {
      "command": {
       "call": {
        "data": {
         "speakerdevice": [
          "media_player.demo_media_player_6"
         ]
        },
        "domain": "script",
        "service": "demo_toggle_speaker_mute"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-mute",
     "iconRotationDegrees": 0,
     "label": "Mute"
    },
    "volumeTitle": "Soundbar Volume",
    "volumeUp": {
     "action": {
      "command": {
       "call": {
        "data": {},
        "domain": "media_player",
        "service": "demo_volume_up",
        "target": "media_player.demo_media_player_6"
       },
       "optimistic": [],
       "type": "service"
      },
      "type": "command"
     },
     "icon": "mdi:volume-plus",
     "iconRotationDegrees": 0,
     "label": "Volume Up"
    }
   }
  ],
  "scriptPowerDevices": [
   {
    "activeEntityId": "input_boolean.demo_switch_1",
    "offScript": "demo_room_power_toggle",
    "onScript": "demo_room_console_2",
    "symbol": "power"
   },
   {
    "activeEntityId": "input_boolean.demo_input_boolean_5",
    "offScript": "demo_room_power_toggle",
    "onScript": "demo_room_media_1",
    "symbol": "power"
   }
  ],
  "sourceSelect": {
   "actions": {
    "consoleSourceToggle": {
     "cases": [
      {
       "command": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_tv_off"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "Off"
         },
         {
          "entityId": "media_player.demo_media_player_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         }
        ],
        "type": "service"
       },
       "states": [
        "Game Console",
        "Game"
       ]
      }
     ],
     "entityId": "sensor.demo_studio_source_1",
     "otherwise": {
      "call": {
       "data": {},
       "domain": "script",
       "service": "demo_studio_console"
      },
      "optimistic": [
       {
        "entityId": "media_player.demo_media_player_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "on"
       },
       {
        "entityId": "media_player.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "on"
       },
       {
        "entityId": "sensor.demo_studio_source_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "Game Console"
       },
       {
        "entityId": "switch.demo_studio_power_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "on"
       },
       {
        "entityId": "switch.demo_studio_light_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "off"
       },
       {
        "entityId": "select.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "HDMI 1"
       }
      ],
      "type": "service"
     },
     "type": "state"
    },
    "consoleToggle": {
     "cases": [
      {
       "command": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_console_off"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_media_player_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "sensor.demo_studio_status_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "plugged"
         }
        ],
        "type": "service"
       },
       "states": [
        "on",
        "playing",
        "paused",
        "linked"
       ]
      }
     ],
     "entityId": "media_player.demo_media_player_1",
     "otherwise": {
      "call": {
       "data": {},
       "domain": "script",
       "service": "demo_studio_console"
      },
      "optimistic": [
       {
        "entityId": "media_player.demo_media_player_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "on"
       },
       {
        "entityId": "media_player.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "on"
       },
       {
        "entityId": "sensor.demo_studio_source_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "Game Console"
       },
       {
        "entityId": "switch.demo_studio_power_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "on"
       },
       {
        "entityId": "switch.demo_studio_light_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "off"
       },
       {
        "entityId": "select.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 90,
        "value": "HDMI 1"
       }
      ],
      "type": "service"
     },
     "type": "state"
    },
    "launcher": {
     "command": {
      "call": {
       "data": {},
       "domain": "script",
       "service": "demo_studio_game"
      },
      "optimistic": [
       {
        "entityId": "media_player.demo_media_player_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 120,
        "value": "on"
       },
       {
        "entityId": "media_player.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 120,
        "value": "on"
       },
       {
        "entityId": "sensor.demo_studio_source_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 120,
        "value": "Game"
       },
       {
        "entityId": "switch.demo_studio_power_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 120,
        "value": "on"
       },
       {
        "entityId": "switch.demo_studio_light_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 120,
        "value": "on"
       },
       {
        "entityId": "select.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 120,
        "value": "HDMI 1"
       }
      ],
      "type": "service"
     },
     "type": "command"
    },
    "pcToggle": {
     "cases": [
      {
       "command": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_tv_off"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "Off"
         },
         {
          "entityId": "media_player.demo_media_player_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         }
        ],
        "type": "service"
       },
       "states": [
        "Computer"
       ]
      }
     ],
     "entityId": "sensor.demo_studio_source_1",
     "otherwise": {
      "call": {
       "data": {},
       "domain": "script",
       "service": "demo_studio_windows_pc"
      },
      "optimistic": [
       {
        "entityId": "media_player.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "on"
       },
       {
        "entityId": "sensor.demo_studio_source_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "Computer"
       },
       {
        "entityId": "switch.demo_studio_power_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "on"
       },
       {
        "entityId": "switch.demo_studio_light_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "off"
       },
       {
        "entityId": "select.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "HDMI 3"
       }
      ],
      "type": "service"
     },
     "type": "state"
    },
    "serverToggle": {
     "cases": [
      {
       "command": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_tv_off"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "Off"
         },
         {
          "entityId": "media_player.demo_media_player_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 180,
          "value": "off"
         }
        ],
        "type": "service"
       },
       "states": [
        "Server"
       ]
      }
     ],
     "entityId": "sensor.demo_studio_source_1",
     "otherwise": {
      "call": {
       "data": {},
       "domain": "script",
       "service": "demo_studio_server"
      },
      "optimistic": [
       {
        "entityId": "media_player.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "on"
       },
       {
        "entityId": "sensor.demo_studio_source_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "Server"
       },
       {
        "entityId": "switch.demo_studio_power_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "on"
       },
       {
        "entityId": "switch.demo_studio_light_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "off"
       },
       {
        "entityId": "select.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 20,
        "value": "HDMI 2"
       }
      ],
      "type": "service"
     },
     "type": "state"
    },
    "tvToggle": {
     "cases": [
      {
       "command": {
        "call": {
         "data": {},
         "domain": "script",
         "service": "demo_studio_tv"
        },
        "optimistic": [
         {
          "entityId": "media_player.demo_studio_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "on"
         },
         {
          "entityId": "sensor.demo_studio_source_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "TV"
         },
         {
          "entityId": "switch.demo_studio_power_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "on"
         },
         {
          "entityId": "switch.demo_studio_light_1",
          "failsOnTimeout": false,
          "revertAfterSeconds": 20,
          "value": "off"
         }
        ],
        "type": "service"
       },
       "states": [
        "off",
        "unavailable",
        "unknown"
       ]
      }
     ],
     "entityId": "media_player.demo_studio_1",
     "otherwise": {
      "call": {
       "data": {},
       "domain": "script",
       "service": "demo_studio_tv_off"
      },
      "optimistic": [
       {
        "entityId": "media_player.demo_studio_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 180,
        "value": "off"
       },
       {
        "entityId": "sensor.demo_studio_source_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 180,
        "value": "Off"
       },
       {
        "entityId": "media_player.demo_media_player_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 180,
        "value": "off"
       },
       {
        "entityId": "switch.demo_studio_power_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 180,
        "value": "off"
       },
       {
        "entityId": "switch.demo_studio_light_1",
        "failsOnTimeout": false,
        "revertAfterSeconds": 180,
        "value": "off"
       }
      ],
      "type": "service"
     },
     "type": "state"
    }
   },
   "activeHoldSeconds": 45,
   "activeStates": [
    "on",
    "playing",
    "paused"
   ],
   "commands": {
    "consoleOff": {
     "call": {
      "data": {},
      "domain": "script",
      "service": "demo_studio_console_off"
     },
     "optimistic": [
      {
       "entityId": "media_player.demo_media_player_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 180,
       "value": "off"
      },
      {
       "entityId": "sensor.demo_studio_status_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 180,
       "value": "plugged"
      }
     ],
     "type": "service"
    },
    "consoleOn": {
     "call": {
      "data": {},
      "domain": "script",
      "service": "demo_studio_console"
     },
     "optimistic": [
      {
       "entityId": "media_player.demo_media_player_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 90,
       "value": "on"
      },
      {
       "entityId": "media_player.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 90,
       "value": "on"
      },
      {
       "entityId": "sensor.demo_studio_source_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 90,
       "value": "Game Console"
      },
      {
       "entityId": "switch.demo_studio_power_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 90,
       "value": "on"
      },
      {
       "entityId": "switch.demo_studio_light_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 90,
       "value": "off"
      },
      {
       "entityId": "select.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 90,
       "value": "HDMI 1"
      }
     ],
     "type": "service"
    },
    "launcher": {
     "call": {
      "data": {},
      "domain": "script",
      "service": "demo_studio_game"
     },
     "optimistic": [
      {
       "entityId": "media_player.demo_media_player_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 120,
       "value": "on"
      },
      {
       "entityId": "media_player.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 120,
       "value": "on"
      },
      {
       "entityId": "sensor.demo_studio_source_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 120,
       "value": "Game"
      },
      {
       "entityId": "switch.demo_studio_power_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 120,
       "value": "on"
      },
      {
       "entityId": "switch.demo_studio_light_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 120,
       "value": "on"
      },
      {
       "entityId": "select.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 120,
       "value": "HDMI 1"
      }
     ],
     "type": "service"
    },
    "pcOn": {
     "call": {
      "data": {},
      "domain": "script",
      "service": "demo_studio_windows_pc"
     },
     "optimistic": [
      {
       "entityId": "media_player.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "on"
      },
      {
       "entityId": "sensor.demo_studio_source_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "Computer"
      },
      {
       "entityId": "switch.demo_studio_power_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "on"
      },
      {
       "entityId": "switch.demo_studio_light_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "off"
      },
      {
       "entityId": "select.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "HDMI 3"
      }
     ],
     "type": "service"
    },
    "serverOn": {
     "call": {
      "data": {},
      "domain": "script",
      "service": "demo_studio_server"
     },
     "optimistic": [
      {
       "entityId": "media_player.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "on"
      },
      {
       "entityId": "sensor.demo_studio_source_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "Server"
      },
      {
       "entityId": "switch.demo_studio_power_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "on"
      },
      {
       "entityId": "switch.demo_studio_light_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "off"
      },
      {
       "entityId": "select.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "HDMI 2"
      }
     ],
     "type": "service"
    },
    "tvOff": {
     "call": {
      "data": {},
      "domain": "script",
      "service": "demo_studio_tv_off"
     },
     "optimistic": [
      {
       "entityId": "media_player.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 180,
       "value": "off"
      },
      {
       "entityId": "sensor.demo_studio_source_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 180,
       "value": "Off"
      },
      {
       "entityId": "media_player.demo_media_player_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 180,
       "value": "off"
      },
      {
       "entityId": "switch.demo_studio_power_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 180,
       "value": "off"
      },
      {
       "entityId": "switch.demo_studio_light_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 180,
       "value": "off"
      }
     ],
     "type": "service"
    },
    "tvOn": {
     "call": {
      "data": {},
      "domain": "script",
      "service": "demo_studio_tv"
     },
     "optimistic": [
      {
       "entityId": "media_player.demo_studio_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "on"
      },
      {
       "entityId": "sensor.demo_studio_source_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "TV"
      },
      {
       "entityId": "switch.demo_studio_power_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "on"
      },
      {
       "entityId": "switch.demo_studio_light_1",
       "failsOnTimeout": false,
       "revertAfterSeconds": 20,
       "value": "off"
      }
     ],
     "type": "service"
    }
   },
   "entityIds": {
    "activeMediaSource": "sensor.demo_studio_source_1",
    "console": "media_player.demo_media_player_1",
    "consoleHdmiStatus": "sensor.demo_studio_status_1",
    "control": "media_player.demo_studio_1",
    "mediaSource": "input_select.demo_studio_source_1",
    "remote": "remote.demo_studio_1",
    "syncBrightness": "number.demo_studio_brightness_1",
    "syncHdmiInput": "select.demo_studio_1",
    "syncIntensity": "select.demo_studio_2",
    "syncLightSync": "switch.demo_studio_light_1",
    "syncMode": "select.demo_studio_mode_1",
    "syncPower": "switch.demo_studio_power_1",
    "volume": "media_player.demo_media_player_6"
   },
   "linkedState": "linked",
   "remoteId": "studio-remote",
   "revertSeconds": {
    "console": 90,
    "consoleOff": 180,
    "launcher": 120,
    "pc": 20,
    "server": 20,
    "sync": 8,
    "tv": 20
   },
   "sources": {
    "console": "Game Console",
    "launcher": "Game",
    "off": "Off",
    "pc": "Computer",
    "server": "Server",
    "tv": "TV"
   },
   "syncHdmiStatusEntityIds": [
    "sensor.demo_studio_status_1",
    "sensor.demo_studio_status_2",
    "sensor.demo_studio_status_3",
    "sensor.demo_studio_status_4"
   ]
  }
 },
 "roomDevices": {
  "airPurifiers": [
   {
    "aqiEntityId": "sensor.demo_living_room_1_air_quality_index",
    "autoModeEntityId": "select.demo_living_room_1_auto_mode",
    "fanEntityId": "fan.demo_living_room_1_purifier",
    "modeEntityId": "select.demo_living_room_1_fan_mode",
    "pm25EntityId": "sensor.demo_living_room_1",
    "roomTitle": "Living Room"
   },
   {
    "aqiEntityId": "sensor.demo_guest_room_1_air_quality_index",
    "autoModeEntityId": "select.demo_guest_room_1_auto_mode",
    "fanEntityId": "fan.demo_guest_room_1_purifier",
    "modeEntityId": "select.demo_guest_room_1_fan_mode",
    "pm25EntityId": "sensor.demo_guest_room_1",
    "roomTitle": "Guest Room"
   },
   {
    "aqiEntityId": "sensor.demo_bedroom_1_2_air_quality_index",
    "autoModeEntityId": "select.demo_bedroom_1_2_auto_mode",
    "fanEntityId": "fan.demo_bedroom_1_2_purifier",
    "modeEntityId": "select.demo_bedroom_1_2_fan_mode",
    "pm25EntityId": "sensor.demo_bedroom_1_2",
    "roomTitle": "Bedroom 1"
   },
   {
    "aqiEntityId": "sensor.demo_office_1_air_quality_index",
    "autoModeEntityId": "select.demo_office_1_auto_mode",
    "fanEntityId": "fan.demo_office_1_purifier",
    "modeEntityId": "select.demo_office_1_fan_mode",
    "pm25EntityId": "sensor.demo_office_1",
    "roomTitle": "Office"
   },
   {
    "aqiEntityId": "sensor.demo_sensor_17_air_quality_index",
    "autoModeEntityId": "select.demo_sensor_17_auto_mode",
    "fanEntityId": "fan.demo_sensor_17_purifier",
    "modeEntityId": "select.demo_sensor_17_fan_mode",
    "pm25EntityId": "sensor.demo_sensor_17",
    "roomTitle": "Studio"
   },
   {
    "aqiEntityId": "sensor.demo_media_room_1_air_quality_index",
    "autoModeEntityId": "select.demo_media_room_1_auto_mode",
    "fanEntityId": "fan.demo_media_room_1_purifier",
    "modeEntityId": "select.demo_media_room_1_fan_mode",
    "pm25EntityId": "sensor.demo_media_room_1",
    "roomTitle": "Media room"
   }
  ],
  "bathroomFans": [
   {
    "autoUnlockEntityId": "input_boolean.demo_fan_1",
    "deadlineEntityId": "input_datetime.demo_fan_1",
    "id": "guest",
    "lockEntityId": "input_boolean.demo_lock_1",
    "pendingEntityId": "input_boolean.demo_fan_2",
    "powerEntityId": "switch.demo_fan_1",
    "roomTitle": "Guest Bathroom",
    "scriptService": "demo_guest_bathroom_fan_command",
    "timerEntityId": "timer.demo_fan_1"
   },
   {
    "autoUnlockEntityId": "input_boolean.demo_bathroom_1_fan_1",
    "deadlineEntityId": "input_datetime.demo_bathroom_1_fan_1",
    "id": "primary",
    "lockEntityId": "input_boolean.demo_bathroom_1_lock_1",
    "pendingEntityId": "input_boolean.demo_bathroom_1_fan_2",
    "powerEntityId": "switch.demo_bathroom_1_fan_1",
    "roomTitle": "Bathroom 1",
    "scriptService": "demo_bathroom_1_fan_command",
    "timerEntityId": "timer.demo_bathroom_1_fan_1"
   }
  ],
  "grills": [
   {
    "details": [
     {
      "entityId": "sensor.demo_sensor_18",
      "icon": "mdi:thermometer",
      "title": "Probe 1"
     },
     {
      "entityId": "sensor.demo_level_1",
      "icon": "mdi:percent",
      "title": "Fuel Level"
     },
     {
      "entityId": "switch.demo_enabled_1",
      "icon": "mdi:fire",
      "title": "Keep Warm"
     },
     {
      "entityId": "switch.demo_enabled_2",
      "icon": "mdi:smoke",
      "title": "Smoke Boost"
     }
    ],
    "roomTitle": "Back Deck",
    "stateEntityId": "sensor.demo_state_1",
    "title": "Grill Probe"
   }
  ],
  "humidifiers": [
   {
    "applyProfileScriptService": "demo_bedroom_1_humidifier_apply_profile",
    "currentHumidityEntityId": "sensor.demo_humidity_1",
    "currentTemperatureEntityId": "sensor.demo_temperature_1",
    "displayEntityId": "switch.demo_switch_1",
    "humidifyingEntityId": "binary_sensor.demo_binary_sensor_6",
    "id": "bedroom-1-unit1",
    "mistLevelEntityId": "number.demo_level_1",
    "modeEntityId": "select.demo_mode_1",
    "powerEntityId": "switch.demo_power_1",
    "scheduleEnabledEntityId": "input_boolean.demo_bedroom_1_schedule_1",
    "scheduleEntityId": "schedule.demo_bedroom_1_1",
    "scheduleId": "demo_bedroom_1_humidifier",
    "setLevelScriptService": "demo_bedroom_1_humidifier_set_level",
    "tankRemovedEntityId": "binary_sensor.demo_binary_sensor_7",
    "targetHumidityEntityId": "number.demo_humidity_1",
    "timerMinutesEntityId": "number.demo_timer_1",
    "timerRemainingEntityId": "sensor.demo_timer_1",
    "title": "Bedroom 1 Humidifier",
    "vacationModeEntityId": "input_boolean.demo_mode_3",
    "warmLevelEntityId": "number.demo_level_2",
    "waterLowEntityId": "binary_sensor.demo_binary_sensor_8"
   }
  ]
 },
 "rooms": {
  "airQualityRooms": [
   {
    "aqiEntityId": "sensor.demo_living_room_2",
    "colorEntityId": "input_text.demo_living_room_color_1",
    "pm25EntityId": "sensor.demo_living_room_1",
    "title": "Living Room"
   },
   {
    "aqiEntityId": "sensor.demo_guest_room_2",
    "colorEntityId": "input_text.demo_guest_room_color_1",
    "pm25EntityId": "sensor.demo_guest_room_1",
    "title": "Guest Room"
   },
   {
    "aqiEntityId": "sensor.demo_office_2",
    "colorEntityId": "input_text.demo_office_color_1",
    "pm25EntityId": "sensor.demo_office_1",
    "title": "Office"
   },
   {
    "aqiEntityId": "sensor.demo_bedroom_1_3",
    "colorEntityId": "input_text.demo_bedroom_1_color_1",
    "pm25EntityId": "sensor.demo_bedroom_1_2",
    "title": "Bedroom 1"
   },
   {
    "aqiEntityId": "sensor.demo_sensor_19",
    "colorEntityId": "input_text.demo_studio_color_1",
    "pm25EntityId": "sensor.demo_sensor_17",
    "title": "Studio"
   },
   {
    "aqiEntityId": "sensor.demo_media_room_2",
    "colorEntityId": "input_text.demo_media_room_color_1",
    "pm25EntityId": "sensor.demo_media_room_1",
    "title": "Media room"
   }
  ],
  "climateGroups": [
   {
    "colorEntityId": "input_text.demo_living_room_color_2",
    "entityId": "input_text.demo_living_room_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_living_room_color_3",
      "contactCount": 1,
      "entityId": "sensor.demo_living_room_temperature_1",
      "title": "Back Wall"
     },
     {
      "colorEntityId": "input_text.demo_living_room_color_4",
      "contactCount": 1,
      "entityId": "sensor.demo_living_room_temperature_2",
      "title": "Bar"
     },
     {
      "colorEntityId": "input_text.demo_living_room_color_5",
      "contactCount": 1,
      "entityId": "sensor.demo_living_room_temperature_3",
      "title": "Kitchen Wall"
     },
     {
      "colorEntityId": "input_text.demo_living_room_color_6",
      "contactCount": 1,
      "entityId": "sensor.demo_living_room_temperature_4",
      "title": "Fireplace"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_living_room_1",
      "title": "Vents"
     }
    ],
    "room": "Living Room"
   },
   {
    "colorEntityId": "input_text.demo_guest_room_color_2",
    "entityId": "input_text.demo_guest_room_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_guest_room_presence_1",
      "contactCount": 1,
      "entityId": "sensor.demo_guest_room_temperature_1",
      "title": "Presence"
     },
     {
      "colorEntityId": "input_text.demo_guest_room_color_3",
      "contactCount": 1,
      "entityId": "sensor.demo_guest_room_temperature_2",
      "title": "Closet"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_guest_room_vent_1",
      "title": "Vent"
     }
    ],
    "room": "Guest Room"
   },
   {
    "colorEntityId": "input_text.demo_bedroom_1_color_2",
    "entityId": "input_text.demo_bedroom_1_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_bedroom_1_color_3",
      "contactCount": 1,
      "entityId": "sensor.demo_bedroom_1_temperature_1",
      "title": "Window"
     },
     {
      "colorEntityId": "input_text.demo_bedroom_1_color_4",
      "contactCount": 1,
      "entityId": "sensor.demo_bedroom_1_temperature_2",
      "title": "Bed"
     },
     {
      "colorEntityId": "input_text.demo_bedroom_1_color_5",
      "contactCount": 1,
      "entityId": "sensor.demo_bedroom_1_temperature_3",
      "title": "Bathroom"
     },
     {
      "colorEntityId": "input_text.demo_bedroom_1_color_6",
      "contactCount": 1,
      "entityId": "sensor.demo_bedroom_1_temperature_4",
      "title": "Closet"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_bedroom_1_1",
      "title": "Vents"
     }
    ],
    "room": "Bedroom 1"
   },
   {
    "colorEntityId": "input_text.demo_gym_color_1",
    "entityId": "input_text.demo_gym_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_gym_presence_1",
      "contactCount": 1,
      "entityId": "sensor.demo_gym_temperature_1",
      "title": "Presence"
     },
     {
      "colorEntityId": "input_text.demo_gym_color_2",
      "contactCount": 1,
      "entityId": "sensor.demo_hallway_temperature_1",
      "title": "Door"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_gym_vent_1",
      "title": "Vent"
     }
    ],
    "room": "Gym"
   },
   {
    "colorEntityId": "input_text.demo_hallway_color_1",
    "entityId": "input_text.demo_hallway_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_entryway_color_1",
      "contactCount": 1,
      "entityId": "sensor.demo_entryway_temperature_1",
      "title": "Entry"
     },
     {
      "colorEntityId": "input_text.demo_gym_color_2",
      "contactCount": 1,
      "entityId": "sensor.demo_hallway_temperature_1",
      "title": "Guest Room"
     },
     {
      "colorEntityId": "input_text.demo_office_color_2",
      "contactCount": 1,
      "entityId": "sensor.demo_hallway_temperature_2",
      "title": "Office"
     }
    ],
    "room": "Hallway"
   },
   {
    "colorEntityId": "input_text.demo_office_color_3",
    "entityId": "input_text.demo_office_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_office_color_2",
      "contactCount": 1,
      "entityId": "sensor.demo_hallway_temperature_2",
      "title": "Door"
     },
     {
      "colorEntityId": "input_text.demo_office_presence_1",
      "contactCount": 1,
      "entityId": "sensor.demo_office_temperature_1",
      "title": "Presence"
     },
     {
      "colorEntityId": "input_text.demo_office_color_4",
      "contactCount": 1,
      "entityId": "sensor.demo_office_temperature_2",
      "title": "Closet"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_office_vent_1",
      "title": "Vent"
     }
    ],
    "room": "Office"
   },
   {
    "colorEntityId": "input_text.demo_kitchen_color_1",
    "entityId": "input_text.demo_kitchen_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_kitchen_presence_1",
      "contactCount": 1,
      "entityId": "sensor.demo_kitchen_temperature_1",
      "title": "Kitchen"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_kitchen_vent_1",
      "title": "Vent"
     }
    ],
    "room": "Kitchen"
   },
   {
    "colorEntityId": "input_text.demo_dining_room_color_1",
    "entityId": "input_text.demo_dining_room_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_dining_room_presence_1",
      "contactCount": 1,
      "entityId": "sensor.demo_dining_room_temperature_1",
      "title": "Presence"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_dining_room_vent_1",
      "title": "Vent"
     }
    ],
    "room": "Dining Room"
   },
   {
    "colorEntityId": "input_text.demo_studio_color_2",
    "entityId": "input_text.demo_studio_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_kitchenette_color_1",
      "contactCount": 1,
      "entityId": "sensor.demo_kitchenette_temperature_1",
      "title": "Kitchenette"
     },
     {
      "colorEntityId": "input_text.demo_studio_color_3",
      "contactCount": 1,
      "entityId": "sensor.demo_studio_temperature_1",
      "title": "North Wall"
     },
     {
      "colorEntityId": "input_text.demo_studio_color_4",
      "contactCount": 1,
      "entityId": "sensor.demo_studio_temperature_2",
      "title": "Door"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_studio_vent_1",
      "title": "Vent"
     }
    ],
    "room": "Studio"
   },
   {
    "colorEntityId": "input_text.demo_media_room_color_2",
    "entityId": "input_text.demo_media_room_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_media_room_presence_1",
      "contactCount": 1,
      "entityId": "sensor.demo_media_room_temperature_1",
      "title": "Presence"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_media_room_1",
      "title": "Vents"
     }
    ],
    "room": "Media room"
   },
   {
    "colorEntityId": "input_text.demo_downstairs_hallway_color_1",
    "entityId": "input_text.demo_downstairs_hallway_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_downstairs_hallway_color_1",
      "contactCount": 1,
      "entityId": "sensor.demo_downstairs_hallway_temperature_1",
      "title": "Presence"
     }
    ],
    "room": "Downstairs Hallway"
   },
   {
    "colorEntityId": "input_text.demo_color_3",
    "entityId": "input_text.demo_input_text_3",
    "items": [
     {
      "colorEntityId": "input_text.demo_presence_1",
      "contactCount": 1,
      "entityId": "sensor.demo_temperature_2",
      "title": "Presence"
     },
     {
      "colorEntityId": "input_text.demo_color_4",
      "contactCount": 1,
      "entityId": "sensor.demo_temperature_3",
      "title": "Entry"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_vent_1",
      "title": "Vent"
     }
    ],
    "room": "Guest Bathroom"
   },
   {
    "colorEntityId": "input_text.demo_bathroom_1_color_1",
    "entityId": "input_text.demo_bathroom_1_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_bathroom_1_presence_1",
      "contactCount": 1,
      "entityId": "sensor.demo_bathroom_1_temperature_1",
      "title": "Presence"
     },
     {
      "contactCount": 1,
      "entityId": "cover.demo_bathroom_1_vent_1",
      "title": "Vent"
     }
    ],
    "room": "Bathroom 1"
   },
   {
    "colorEntityId": "input_text.demo_front_door_color_1",
    "entityId": "input_text.demo_front_door_door_1",
    "items": [
     {
      "colorEntityId": "input_text.demo_entryway_color_1",
      "contactCount": 1,
      "entityId": "sensor.demo_front_door_temperature_1",
      "title": "Front Door"
     }
    ],
    "room": "Entryway"
   }
  ],
  "contactGroups": [
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_front_door_contact_1",
      "title": "Front Door"
     }
    ],
    "room": "Entryway"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_office_contact_1",
      "title": "Computer Window"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_office_contact_2",
      "title": "Window"
     }
    ],
    "room": "Office"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_living_room_contact_1",
      "title": "Window"
     }
    ],
    "room": "Living Room"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_garage_contact_1",
      "title": "Garage Door"
     }
    ],
    "room": "Garage"
   },
   {
    "items": [
     {
      "contactCount": 2,
      "entityId": "binary_sensor.demo_bedroom_1_contact_1",
      "title": "Side Windows"
     }
    ],
    "room": "Bedroom 1"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_dining_room_contact_1",
      "title": "Dining Room Door"
     }
    ],
    "room": "Dining Room"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_kitchen_contact_1",
      "title": "Kitchen Door"
     }
    ],
    "room": "Kitchen"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_studio_contact_1",
      "title": "Studio Door"
     }
    ],
    "room": "Studio"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_media_room_contact_1",
      "title": "Media room Door"
     }
    ],
    "room": "Media room"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_guest_room_contact_1",
      "title": "Window"
     }
    ],
    "room": "Guest Room"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_gym_contact_1",
      "title": "Window"
     }
    ],
    "room": "Gym"
   }
  ],
  "grid": {
   "accessIncrementScript": "script.demo_script_2",
   "items": [
    {
     "accessCounterEntityId": "counter.demo_living_room_1",
     "accessKey": "living-room",
     "color": {
      "blue": 0.6431372549019608,
      "green": 0.807843137254902,
      "opacity": 1,
      "red": 0.8549019607843137
     },
     "icon": "mdi:sofa",
     "path": "living-room",
     "title": "Living Room"
    },
    {
     "accessCounterEntityId": "counter.demo_guest_room_1",
     "accessKey": "guest-room",
     "color": {
      "blue": 0.5725490196078431,
      "green": 0.7568627450980392,
      "opacity": 1,
      "red": 0.2
     },
     "icon": "mdi:bed",
     "path": "guest-room",
     "title": "Guest Room"
    },
    {
     "accessCounterEntityId": "counter.demo_gym_1",
     "accessKey": "gym",
     "color": {
      "blue": 0.10196078431372549,
      "green": 0.4588235294117647,
      "opacity": 1,
      "red": 0.8352941176470589
     },
     "icon": "mdi:dumbbell",
     "path": "gym",
     "title": "Gym"
    },
    {
     "accessCounterEntityId": "counter.demo_bedroom_1_1",
     "accessKey": "bedroom-1",
     "color": {
      "blue": 0.8431372549019608,
      "green": 0.12941176470588237,
      "opacity": 1,
      "red": 0.0784313725490196
     },
     "icon": "mdi:bed-king",
     "path": "bedroom-1",
     "title": "Bedroom 1"
    },
    {
     "accessCounterEntityId": "counter.demo_office_1",
     "accessKey": "office",
     "color": {
      "blue": 0.807843137254902,
      "green": 0.8588235294117647,
      "opacity": 1,
      "red": 0.0784313725490196
     },
     "icon": "mdi:desktop-tower",
     "path": "office",
     "title": "Office"
    },
    {
     "accessCounterEntityId": "counter.demo_hallway_1",
     "accessKey": "hallway",
     "color": {
      "blue": 0.12156862745098039,
      "green": 0.19215686274509805,
      "opacity": 1,
      "red": 0.2549019607843137
     },
     "icon": "mdi:door-open",
     "path": "hallway",
     "title": "Hallway"
    },
    {
     "accessCounterEntityId": "counter.demo_kitchen_1",
     "accessKey": "kitchen",
     "color": {
      "blue": 0.23529411764705882,
      "green": 0.7843137254901961,
      "opacity": 1,
      "red": 0.6941176470588235
     },
     "icon": "mdi:stove",
     "path": "kitchen",
     "title": "Kitchen"
    },
    {
     "accessCounterEntityId": "counter.demo_studio_1",
     "accessKey": "studio",
     "color": {
      "blue": 0.7294117647058823,
      "green": 0.07058823529411765,
      "opacity": 1,
      "red": 0.7176470588235294
     },
     "icon": "mdi:music",
     "path": "studio",
     "title": "Studio"
    },
    {
     "accessCounterEntityId": "counter.demo_garage_1",
     "accessKey": "garage",
     "color": {
      "blue": 0.047058823529411764,
      "green": 0.047058823529411764,
      "opacity": 1,
      "red": 0.8745098039215686
     },
     "icon": "mdi:garage",
     "path": "garage",
     "title": "Garage"
    },
    {
     "accessCounterEntityId": "counter.demo_media_room_1",
     "accessKey": "media-room",
     "color": {
      "blue": 0.00392156862745098,
      "green": 0,
      "opacity": 1,
      "red": 0
     },
     "icon": "mdi:movie-open",
     "path": "media-room",
     "title": "Media room"
    },
    {
     "accessCounterEntityId": "counter.demo_back_deck_1",
     "accessKey": "back-deck",
     "color": {
      "blue": 0.023529411764705882,
      "green": 0.30196078431372547,
      "opacity": 1,
      "red": 0.0196078431372549
     },
     "icon": "mdi:grill",
     "path": "back-deck",
     "title": "Back Deck"
    },
    {
     "accessCounterEntityId": "counter.demo_downstairs_hallway_1",
     "accessKey": "downstairs-hallway",
     "color": {
      "blue": 0.796078431372549,
      "green": 0.9254901960784314,
      "opacity": 1,
      "red": 0.9176470588235294
     },
     "icon": "mdi:stairs",
     "path": "downstairs-hallway",
     "title": "Downstairs Hallway"
    },
    {
     "accessCounterEntityId": "counter.demo_counter_1",
     "accessKey": "guest-bathroom",
     "color": {
      "blue": 0.8784313725490196,
      "green": 0.8901960784313725,
      "opacity": 1,
      "red": 0.16862745098039217
     },
     "icon": "mdi:shower",
     "path": "guest-bathroom",
     "title": "Guest Bathroom"
    },
    {
     "accessCounterEntityId": "counter.demo_bathroom_1_1",
     "accessKey": "bathroom-1",
     "color": {
      "blue": 0.36470588235294116,
      "green": 0.36470588235294116,
      "opacity": 1,
      "red": 0.37254901960784315
     },
     "icon": "mdi:bathtub",
     "path": "bathroom-1",
     "title": "Bathroom 1"
    },
    {
     "accessCounterEntityId": "counter.demo_dining_room_1",
     "accessKey": "dining-room",
     "color": {
      "blue": 0.45098039215686275,
      "green": 0.7019607843137254,
      "opacity": 1,
      "red": 0.8509803921568627
     },
     "icon": "mdi:silverware-fork-knife",
     "path": "dining-room",
     "title": "Dining Room"
    },
    {
     "accessCounterEntityId": "counter.demo_entryway_1",
     "accessKey": "entryway",
     "color": {
      "blue": 0,
      "green": 0.8509803921568627,
      "opacity": 1,
      "red": 0.9803921568627451
     },
     "icon": "mdi:door",
     "path": "entryway",
     "title": "Entryway"
    }
   ]
  },
  "lightGroups": [
   {
    "entityId": "light.demo_living_room_item_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_living_room_light_1",
      "title": "Front Left"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_living_room_light_2",
      "title": "Front Right"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_living_room_light_3",
      "title": "Back Left"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_living_room_light_4",
      "title": "Back Right"
     }
    ],
    "room": "Living Room"
   },
   {
    "entityId": "light.demo_guest_room_item_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_guest_room_light_1",
      "title": "TV Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_guest_room_light_2",
      "title": "Bed Light"
     }
    ],
    "room": "Guest Room"
   },
   {
    "entityId": "light.demo_bedroom_1_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_bedroom_1_window_1",
      "title": "Window Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_bedroom_1_light_1",
      "title": "Bathroom Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_bedroom_1_door_1",
      "title": "Door Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_light_2",
      "resident": "resident_1",
      "title": "Alex Nightstand"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_light_3",
      "resident": "resident_2",
      "title": "Sam Nightstand"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_bedroom_1_light_2",
      "title": "Closet Light"
     }
    ],
    "room": "Bedroom 1"
   },
   {
    "entityId": "light.demo_bedroom_1_light_2",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_bedroom_1_light_2",
      "title": "Closet Light"
     }
    ],
    "room": "Bedroom 1 Closet"
   },
   {
    "entityId": "light.demo_gym_light_item_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_gym_light_item_1",
      "title": "Gym Light"
     }
    ],
    "room": "Gym"
   },
   {
    "entityId": "light.demo_hallway_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_hallway_light_1",
      "title": "Entry Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_hallway_light_2",
      "title": "Gym Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_guest_room_light_3",
      "title": "Guest Room Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_hallway_light_3",
      "title": "Office Light"
     }
    ],
    "room": "Hallway"
   },
   {
    "entityId": "light.demo_office_light_item_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_office_light_item_1",
      "title": "Office Light"
     }
    ],
    "room": "Office"
   },
   {
    "entityId": "light.demo_kitchen_item_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_kitchen_light_1",
      "title": "Table Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_kitchen_door_1",
      "title": "Door Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_kitchen_light_2",
      "title": "Counter Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_kitchen_light_3",
      "title": "Sink Light"
     }
    ],
    "room": "Kitchen"
   },
   {
    "entityId": "light.demo_dining_room_switch_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_dining_room_switch_1",
      "title": "Dining Room Light"
     }
    ],
    "room": "Dining Room"
   },
   {
    "entityId": "light.demo_back_deck_item_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_light_4",
      "title": "Patio Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_light_5",
      "title": "Couches Light"
     }
    ],
    "room": "Back Deck"
   },
   {
    "entityId": "light.demo_studio_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_studio_light_1",
      "title": "Fireplace Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_color_1",
      "title": "Window Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_color_2",
      "title": "Entry Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_color_3",
      "title": "Studio Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_color_4",
      "title": "Bathroom Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_color_5",
      "title": "Sofa Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_color_6",
      "title": "Server Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_color_7",
      "title": "TV Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_light_6",
      "title": "TV Left Light"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_light_7",
      "title": "TV Right Light"
     }
    ],
    "room": "Studio"
   },
   {
    "entityId": "light.demo_media_room_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_media_room_light_1",
      "title": "Front Screen"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_media_room_light_2",
      "title": "Front Right"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_media_room_light_3",
      "title": "Front Back"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_media_room_light_4",
      "title": "Rear Front"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_media_room_light_5",
      "title": "Rear Back"
     },
     {
      "contactCount": 1,
      "entityId": "light.demo_media_room_light_6",
      "title": "Rear Right"
     }
    ],
    "room": "Media room"
   },
   {
    "entityId": "light.demo_downstairs_hallway_light_item_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_downstairs_hallway_light_item_1",
      "title": "Downstairs Hallway Light"
     }
    ],
    "room": "Downstairs Hallway"
   },
   {
    "entityId": "light.demo_switch_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_switch_1",
      "title": "Guest Bathroom Light"
     }
    ],
    "room": "Guest Bathroom"
   },
   {
    "entityId": "light.demo_bathroom_1_switch_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_bathroom_1_switch_1",
      "title": "Bathroom 1 Light"
     }
    ],
    "room": "Bathroom 1"
   },
   {
    "entityId": "switch.demo_entryway_light_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "switch.demo_entryway_light_1",
      "title": "Entryway Light"
     }
    ],
    "room": "Entryway"
   },
   {
    "entityId": "light.demo_garage_camera_1",
    "items": [
     {
      "contactCount": 1,
      "entityId": "light.demo_garage_camera_1",
      "title": "Floodlight"
     }
    ],
    "room": "Driveway"
   }
  ],
  "occupancyGroups": [
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_living_room_presence_1",
      "title": "Back Wall"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_living_room_presence_2",
      "title": "Bar"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_living_room_presence_3",
      "title": "Kitchen Wall"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_living_room_presence_4",
      "title": "Fireplace"
     }
    ],
    "room": "Living Room"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_entryway_presence_1",
      "title": "Entryway"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_hallway_presence_1",
      "title": "Bathroom"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_hallway_presence_2",
      "title": "Office"
     }
    ],
    "room": "Hallway"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_kitchen_presence_1",
      "title": "Kitchen"
     }
    ],
    "room": "Kitchen"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_guest_room_presence_1",
      "title": "Guest Room"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_guest_room_presence_2",
      "title": "Closet"
     }
    ],
    "room": "Guest Room"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_gym_presence_1",
      "title": "Gym"
     }
    ],
    "room": "Gym"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_office_presence_1",
      "title": "Office"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_office_presence_2",
      "title": "Closet"
     }
    ],
    "room": "Office"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_bedroom_1_presence_1",
      "title": "Bedroom 1"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_bedroom_1_presence_2",
      "title": "Bed"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_bedroom_1_presence_3",
      "title": "Bathroom"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_bedroom_1_presence_4",
      "title": "Closet"
     }
    ],
    "room": "Bedroom 1"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_bedroom_1_presence_4",
      "title": "Closet"
     }
    ],
    "room": "Bedroom 1 Closet"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_presence_1",
      "title": "Guest Bathroom"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_presence_2",
      "title": "Entry"
     }
    ],
    "room": "Guest Bathroom"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_bathroom_1_presence_1",
      "title": "Bathroom 1"
     }
    ],
    "room": "Bathroom 1"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_studio_presence_1",
      "title": "North Wall"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_kitchenette_presence_1",
      "title": "Kitchenette"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_studio_presence_2",
      "title": "Door"
     }
    ],
    "room": "Studio"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_dining_room_presence_1",
      "title": "Dining Room"
     }
    ],
    "room": "Dining Room"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_media_room_presence_1",
      "title": "Media room"
     }
    ],
    "room": "Media room"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_entryway_presence_1",
      "title": "Entryway Occupancy"
     },
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_front_door_presence_1",
      "title": "Front Door"
     }
    ],
    "room": "Entryway"
   },
   {
    "items": [
     {
      "contactCount": 1,
      "entityId": "binary_sensor.demo_downstairs_hallway_presence_1",
      "title": "Downstairs Hallway"
     }
    ],
    "room": "Downstairs Hallway"
   }
  ],
  "pages": [
   {
    "id": "living-room",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_living_room_item_1",
      "icon": "mdi:lightbulb-group",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-living-room",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Lights"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_living_room_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-living-room",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_living_room_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "living-room-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_living_room_contact_1",
      "icon": "mdi:window-closed",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "window-living-room",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Window"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "sensor.demo_living_room_1",
      "icon": "mdi:air-purifier",
      "isFullWidth": false,
      "kind": "air",
      "modalItems": [],
      "sheet": "air-purifier",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Air Quality"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_living_room_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_living_room_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent 1"
         },
         {
          "entityId": "cover.demo_living_room_vent_2",
          "icon": "mdi:air-filter",
          "title": "Vent 2"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vents"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "select.demo_living_room_mode_1",
        "icon": "mdi:fan",
        "isFullWidth": false,
        "kind": "air",
        "modalEntityId": "sensor.demo_living_room_1",
        "modalItems": [],
        "sheet": "air-purifier",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "select.demo_living_room_mode_1",
         "fan.demo_living_room_1"
        ],
        "title": "Air Purifier"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "vacuum.demo_vacuum_1",
        "icon": "mdi:robot-vacuum",
        "isFullWidth": true,
        "kind": "vacuum",
        "modalItems": [],
        "modalTitle": "Robot Vacuum",
        "sheet": "robot-vacuum",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Main Floor"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Devices"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "media_player.demo_living_room_1",
        "icon": "mdi:remote",
        "isFullWidth": false,
        "kind": "media",
        "modalItems": [],
        "semantics": {
         "type": "modal"
        },
        "sheet": "living-room-streamer",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Living Room Remote"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Remote"
     },
     {
      "cards": [],
      "layout": {
       "appLaunch": {
        "remoteId": "living-room-streamer"
       }
      },
      "showOnRoomPage": true,
      "title": "Quick App Launch"
     }
    ],
    "title": "Living Room"
   },
   {
    "id": "guest-room",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_guest_room_item_1",
      "icon": "mdi:lightbulb-group",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-guest-room",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Lights"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_guest_room_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-guest-room",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_guest_room_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "guest-room-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_guest_room_contact_1",
      "icon": "mdi:window-closed",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "window-guest-room",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Window"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "sensor.demo_guest_room_1",
      "icon": "mdi:air-purifier",
      "isFullWidth": false,
      "kind": "air",
      "modalItems": [],
      "sheet": "air-purifier",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Air Quality"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_guest_room_vent_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_guest_room_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vent"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "select.demo_guest_room_mode_1",
        "icon": "mdi:fan",
        "isFullWidth": false,
        "kind": "air",
        "modalEntityId": "sensor.demo_guest_room_1",
        "modalItems": [],
        "sheet": "air-purifier",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "select.demo_guest_room_mode_1",
         "fan.demo_guest_room_1"
        ],
        "title": "Air Purifier"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     }
    ],
    "title": "Guest Room"
   },
   {
    "id": "bedroom-1",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_bedroom_1_1",
      "icon": "mdi:lightbulb-group",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-bedroom-1",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Lights"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_bedroom_1_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-bedroom-1",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_bedroom_1_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "bedroom-1-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_bedroom_1_contact_1",
      "icon": "mdi:window-closed",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "window-bedroom-1",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Window"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "sensor.demo_bedroom_1_2",
      "icon": "mdi:air-purifier",
      "isFullWidth": false,
      "kind": "air",
      "modalItems": [],
      "sheet": "air-purifier",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Air Quality"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "sensor.demo_bedroom_1_light_1",
        "icon": "mdi:weather-sunset-up",
        "isFullWidth": false,
        "kind": "wake-light",
        "modalItems": [],
        "semantics": {
         "type": "modal"
        },
        "sheet": "wake-light-alarms-bedroom-1",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Wake-Light Alarms"
       }
      ],
      "layout": {
       "twoColumnFill": {}
      },
      "showOnRoomPage": true,
      "title": "Sleep & Wake"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": true,
        "disabledStates": [],
        "entityId": "climate.demo_climate_1",
        "icon": "mdi:bed",
        "isFullWidth": false,
        "kind": "climate",
        "modalItems": [],
        "resident": "resident_1",
        "residentLabel": {
         "bedSide": {}
        },
        "sheet": "alexs-bed",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Alex's Bed"
       },
       {
        "activeStates": [],
        "climateActionTone": true,
        "disabledStates": [],
        "entityId": "climate.demo_climate_2",
        "icon": "mdi:bed",
        "isFullWidth": false,
        "kind": "climate",
        "modalItems": [],
        "resident": "resident_2",
        "residentLabel": {
         "bedSide": {}
        },
        "sheet": "sams-bed",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Sam's Bed"
       }
      ],
      "layout": {
       "twoColumnFill": {}
      },
      "showOnRoomPage": true,
      "title": "Bed"
     },
     {
      "cards": [
       {
        "activeStates": [
         "idle",
         "paused",
         "playing"
        ],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "media_player.demo_bedroom_1_1",
        "icon": "mdi:television-classic",
        "isFullWidth": true,
        "kind": "media",
        "modalItems": [],
        "sheet": "bedroom-1-streamer-tv",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Streamer"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Media"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_bedroom_1_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_bedroom_1_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent 1"
         },
         {
          "entityId": "cover.demo_bedroom_1_vent_2",
          "icon": "mdi:air-filter",
          "title": "Vent 2"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vents"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "select.demo_bedroom_1_mode_1",
        "icon": "mdi:fan",
        "isFullWidth": false,
        "kind": "air",
        "modalEntityId": "sensor.demo_bedroom_1_2",
        "modalItems": [],
        "sheet": "air-purifier",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "select.demo_bedroom_1_mode_1",
         "fan.demo_bedroom_1_1"
        ],
        "title": "Air Purifier"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "switch.demo_power_1",
        "icon": "mdi:air-humidifier",
        "isFullWidth": false,
        "kind": "humidifier",
        "modalItems": [],
        "sheet": "humidifier-bedroom-1",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "switch.demo_power_1",
         "sensor.demo_humidity_1"
        ],
        "title": "Humidifier"
       }
      ],
      "layout": {
       "twoColumnFill": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     }
    ],
    "title": "Bedroom 1"
   },
   {
    "id": "gym",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_gym_light_item_1",
      "icon": "mdi:lightbulb",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-gym",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Light"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_gym_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-gym",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_gym_presence_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "gym-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_gym_contact_1",
      "icon": "mdi:window-closed",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "window-gym",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Window"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_gym_vent_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_gym_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vent"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     }
    ],
    "title": "Gym"
   },
   {
    "id": "hallway",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_hallway_1",
      "icon": "mdi:lightbulb-group",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-hallway",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Lights"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_hallway_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-hallway",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_hallway_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "hallway-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     }
    ],
    "sections": [],
    "title": "Hallway"
   },
   {
    "id": "office",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_office_light_item_1",
      "icon": "mdi:lightbulb",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-office",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Light"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_office_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-office",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_office_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "office-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_office_2",
      "icon": "mdi:window-closed",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "windows-office",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Windows"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "sensor.demo_office_1",
      "icon": "mdi:air-purifier",
      "isFullWidth": false,
      "kind": "air",
      "modalItems": [],
      "sheet": "air-purifier",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Air Quality"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_office_vent_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_office_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vent"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "select.demo_office_mode_1",
        "icon": "mdi:fan",
        "isFullWidth": false,
        "kind": "air",
        "modalEntityId": "sensor.demo_office_1",
        "modalItems": [],
        "sheet": "air-purifier",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "select.demo_office_mode_1",
         "fan.demo_office_1"
        ],
        "title": "Air Purifier"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     },
     {
      "cards": [
       {
        "action": {
         "action": {
          "cases": [
           {
            "command": {
             "call": {
              "data": {},
              "domain": "input_button",
              "service": "demo_press",
              "target": "input_button.demo_input_button_7"
             },
             "optimistic": [],
             "type": "service"
            },
            "states": [
             "on"
            ]
           }
          ],
          "otherwise": {
           "call": {
            "data": {},
            "domain": "input_button",
            "service": "demo_press",
            "target": "input_button.demo_input_button_8"
           },
           "optimistic": [],
           "type": "service"
          },
          "type": "state"
         },
         "type": "remote"
        },
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "input_boolean.demo_power_2",
        "icon": "mdi:controller",
        "isFullWidth": false,
        "kind": "power",
        "modalItems": [],
        "resident": "resident_1",
        "residentLabel": {
         "pc": {}
        },
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "input_text.demo_power_1"
        ],
        "title": "Alex's PC"
       },
       {
        "action": {
         "action": {
          "cases": [
           {
            "command": {
             "call": {
              "data": {},
              "domain": "input_button",
              "service": "demo_press",
              "target": "input_button.demo_input_button_9"
             },
             "optimistic": [],
             "type": "service"
            },
            "states": [
             "on"
            ]
           }
          ],
          "otherwise": {
           "call": {
            "data": {},
            "domain": "input_button",
            "service": "demo_press",
            "target": "input_button.demo_input_button_10"
           },
           "optimistic": [],
           "type": "service"
          },
          "type": "state"
         },
         "type": "remote"
        },
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "input_boolean.demo_power_3",
        "icon": "mdi:controller",
        "isFullWidth": false,
        "kind": "power",
        "modalItems": [],
        "resident": "resident_2",
        "residentLabel": {
         "pc": {}
        },
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "input_text.demo_power_2"
        ],
        "title": "Sam's PC"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Computers"
     }
    ],
    "title": "Office"
   },
   {
    "id": "kitchen",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_kitchen_item_1",
      "icon": "mdi:lightbulb-group",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-kitchen",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Lights"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_kitchen_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-kitchen",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_kitchen_presence_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "kitchen-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_kitchen_contact_1",
      "icon": "mdi:door",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "door-kitchen",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Door"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "alternate": {
         "entityId": "sensor.demo_program_1",
         "showState": true,
         "subtitleEntityIds": [
          "select.demo_program_1",
          "sensor.demo_program_1"
         ],
         "whenEntityId": "sensor.demo_state_2",
         "whenStates": [
          "run",
          "pause"
         ]
        },
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "select.demo_program_1",
        "icon": "mdi:dishwasher",
        "isFullWidth": true,
        "kind": "appliance",
        "modalItems": [],
        "sheet": "dishwasher",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "sensor.demo_door_1",
         "select.demo_program_1"
        ],
        "title": "Dishwasher"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Appliances"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_kitchen_vent_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_kitchen_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vent"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     }
    ],
    "title": "Kitchen"
   },
   {
    "id": "dining-room",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_dining_room_switch_1",
      "icon": "mdi:lightbulb",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-dining-room",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Light"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_dining_room_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-dining-room",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_dining_room_presence_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "dining-room-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_dining_room_contact_1",
      "icon": "mdi:door",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "door-dining-room",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Door"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_dining_room_vent_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_dining_room_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vent"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     }
    ],
    "title": "Dining Room"
   },
   {
    "id": "back-deck",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_back_deck_item_1",
      "icon": "mdi:lightbulb-group",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-back-deck",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Lights"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_upper_deck_camera_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_back_deck_1",
      "icon": "mdi:door",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "doors-back-deck",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Doors"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [
         "off",
         "unavailable",
         "unknown"
        ],
        "entityId": "sensor.demo_state_1",
        "icon": "mdi:grill",
        "isFullWidth": false,
        "kind": "grill",
        "modalItems": [],
        "sheet": "probe-grills",
        "showState": true,
        "stateColors": {},
        "stateLabels": {
         "off": "Off",
         "unavailable": "Off",
         "unknown": "Off"
        },
        "subtitleEntityIds": [],
        "title": "Grill Probe"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Grill"
     }
    ],
    "title": "Back Deck"
   },
   {
    "id": "studio",
    "optimisticRemoteId": "studio-remote",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_studio_1",
      "icon": "mdi:lightbulb-group",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-studio",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Lights"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_studio_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-studio",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_studio_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "studio-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_studio_contact_1",
      "icon": "mdi:door",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "door-studio",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Door"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "sensor.demo_sensor_17",
      "icon": "mdi:air-purifier",
      "isFullWidth": false,
      "kind": "air",
      "modalItems": [],
      "sheet": "air-purifier",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Air Quality"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_studio_vent_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_studio_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vents"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "select.demo_mode_2",
        "icon": "mdi:fan",
        "isFullWidth": false,
        "kind": "air",
        "modalEntityId": "sensor.demo_sensor_17",
        "modalItems": [],
        "sheet": "air-purifier",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "select.demo_mode_2",
         "fan.demo_fan_1"
        ],
        "title": "Air Purifier"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "media_player.demo_studio_1",
        "icon": "mdi:remote",
        "isFullWidth": false,
        "kind": "media",
        "modalItems": [],
        "semantics": {
         "type": "modal"
        },
        "sheet": "studio-remote",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Studio Remote"
       },
       {
        "action": {
         "action": {
          "cases": [
           {
            "command": {
             "call": {
              "data": {},
              "domain": "script",
              "service": "demo_studio_tv_off"
             },
             "optimistic": [
              {
               "entityId": "media_player.demo_studio_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "sensor.demo_studio_source_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "Off"
              },
              {
               "entityId": "media_player.demo_media_player_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "switch.demo_studio_power_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "switch.demo_studio_light_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              }
             ],
             "type": "service"
            },
            "states": [
             "Game Console",
             "Game"
            ]
           }
          ],
          "entityId": "sensor.demo_studio_source_1",
          "otherwise": {
           "call": {
            "data": {},
            "domain": "script",
            "service": "demo_studio_console"
           },
           "optimistic": [
            {
             "entityId": "media_player.demo_media_player_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 90,
             "value": "on"
            },
            {
             "entityId": "media_player.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 90,
             "value": "on"
            },
            {
             "entityId": "sensor.demo_studio_source_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 90,
             "value": "Game Console"
            },
            {
             "entityId": "switch.demo_studio_power_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 90,
             "value": "on"
            },
            {
             "entityId": "switch.demo_studio_light_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 90,
             "value": "off"
            },
            {
             "entityId": "select.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 90,
             "value": "HDMI 1"
            }
           ],
           "type": "service"
          },
          "type": "state"
         },
         "type": "remote"
        },
        "activeStates": [
         "Game Console",
         "Game"
        ],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "sensor.demo_studio_source_1",
        "icon": "mdi:gamepad",
        "isFullWidth": false,
        "kind": "media",
        "modalItems": [],
        "semantics": {
         "rule": {
          "states": [
           "Game Console",
           "Game"
          ],
          "type": "selectedWhen"
         },
         "type": "rule"
        },
        "showState": true,
        "stateColors": {},
        "stateLabels": {
         "Computer": "Off",
         "Game": "On",
         "Game Console": "On",
         "Off": "Off",
         "Server": "Off",
         "TV": "Off"
        },
        "subtitleEntityIds": [],
        "title": "Game Console"
       },
       {
        "action": {
         "action": {
          "cases": [
           {
            "command": {
             "call": {
              "data": {},
              "domain": "script",
              "service": "demo_studio_tv_off"
             },
             "optimistic": [
              {
               "entityId": "media_player.demo_studio_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "sensor.demo_studio_source_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "Off"
              },
              {
               "entityId": "media_player.demo_media_player_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "switch.demo_studio_power_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "switch.demo_studio_light_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              }
             ],
             "type": "service"
            },
            "states": [
             "Server"
            ]
           }
          ],
          "entityId": "sensor.demo_studio_source_1",
          "otherwise": {
           "call": {
            "data": {},
            "domain": "script",
            "service": "demo_studio_server"
           },
           "optimistic": [
            {
             "entityId": "media_player.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "on"
            },
            {
             "entityId": "sensor.demo_studio_source_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "Server"
            },
            {
             "entityId": "switch.demo_studio_power_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "on"
            },
            {
             "entityId": "switch.demo_studio_light_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "off"
            },
            {
             "entityId": "select.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "HDMI 2"
            }
           ],
           "type": "service"
          },
          "type": "state"
         },
         "type": "remote"
        },
        "activeStates": [
         "Server"
        ],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "sensor.demo_studio_source_1",
        "icon": "mdi:server",
        "isFullWidth": false,
        "kind": "media",
        "modalItems": [],
        "semantics": {
         "rule": {
          "states": [
           "Server"
          ],
          "type": "selectedWhen"
         },
         "type": "rule"
        },
        "showState": true,
        "stateColors": {},
        "stateLabels": {
         "Computer": "Off",
         "Game": "Off",
         "Game Console": "Off",
         "Off": "Off",
         "Server": "On",
         "TV": "Off"
        },
        "subtitleEntityIds": [],
        "title": "Server"
       },
       {
        "action": {
         "action": {
          "cases": [
           {
            "command": {
             "call": {
              "data": {},
              "domain": "script",
              "service": "demo_studio_tv_off"
             },
             "optimistic": [
              {
               "entityId": "media_player.demo_studio_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "sensor.demo_studio_source_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "Off"
              },
              {
               "entityId": "media_player.demo_media_player_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "switch.demo_studio_power_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              },
              {
               "entityId": "switch.demo_studio_light_1",
               "failsOnTimeout": false,
               "revertAfterSeconds": 180,
               "value": "off"
              }
             ],
             "type": "service"
            },
            "states": [
             "Computer"
            ]
           }
          ],
          "entityId": "sensor.demo_studio_source_1",
          "otherwise": {
           "call": {
            "data": {},
            "domain": "script",
            "service": "demo_studio_windows_pc"
           },
           "optimistic": [
            {
             "entityId": "media_player.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "on"
            },
            {
             "entityId": "sensor.demo_studio_source_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "Computer"
            },
            {
             "entityId": "switch.demo_studio_power_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "on"
            },
            {
             "entityId": "switch.demo_studio_light_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "off"
            },
            {
             "entityId": "select.demo_studio_1",
             "failsOnTimeout": false,
             "revertAfterSeconds": 20,
             "value": "HDMI 3"
            }
           ],
           "type": "service"
          },
          "type": "state"
         },
         "type": "remote"
        },
        "activeStates": [
         "Computer"
        ],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "sensor.demo_studio_source_1",
        "icon": "mdi:desktop-classic",
        "isFullWidth": false,
        "kind": "media",
        "modalItems": [],
        "semantics": {
         "rule": {
          "states": [
           "Computer"
          ],
          "type": "selectedWhen"
         },
         "type": "rule"
        },
        "showState": true,
        "stateColors": {},
        "stateLabels": {
         "Computer": "On",
         "Game": "Off",
         "Game Console": "Off",
         "Off": "Off",
         "Server": "Off",
         "TV": "Off"
        },
        "subtitleEntityIds": [],
        "title": "Computer"
       }
      ],
      "layout": {
       "leadRow": {}
      },
      "showOnRoomPage": true,
      "title": "Remote"
     },
     {
      "cards": [],
      "layout": {
       "appLaunch": {
        "remoteId": "studio-remote"
       }
      },
      "showOnRoomPage": false,
      "title": "Quick App Launch"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "vacuum.demo_vacuum_2",
        "icon": "mdi:robot-vacuum",
        "isFullWidth": true,
        "kind": "vacuum",
        "modalItems": [],
        "modalTitle": "Robot Vacuum",
        "sheet": "robot-vacuum",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Studio"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Devices"
     }
    ],
    "title": "Studio"
   },
   {
    "id": "media-room",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_media_room_1",
      "icon": "mdi:lightbulb-group",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-media-room",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Lights"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_media_room_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-media-room",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_media_room_presence_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "media-room-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_media_room_contact_1",
      "icon": "mdi:door",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "door-media-room",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Door"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "sensor.demo_media_room_1",
      "icon": "mdi:air-purifier",
      "isFullWidth": false,
      "kind": "air",
      "modalItems": [],
      "sheet": "air-purifier",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Air Quality"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_media_room_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_media_room_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent 1"
         },
         {
          "entityId": "cover.demo_media_room_vent_2",
          "icon": "mdi:air-filter",
          "title": "Vent 2"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vents"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "select.demo_media_room_mode_1",
        "icon": "mdi:fan",
        "isFullWidth": false,
        "kind": "air",
        "modalEntityId": "sensor.demo_media_room_1",
        "modalItems": [],
        "sheet": "air-purifier",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "select.demo_media_room_mode_1",
         "fan.demo_media_room_1"
        ],
        "title": "Air Purifier"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "media_player.demo_media_player_2",
        "icon": "mdi:projector",
        "isFullWidth": false,
        "kind": "media",
        "modalItems": [],
        "semantics": {
         "type": "modal"
        },
        "sheet": "media-room-streamer",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Media room Remote"
       },
       {
        "action": {
         "action": {
          "command": {
           "call": {
            "data": {},
            "domain": "script",
            "service": "demo_media_room_handheld_switch"
           },
           "optimistic": [],
           "type": "service"
          },
          "type": "command"
         },
         "type": "remote"
        },
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "input_boolean.demo_switch_1",
        "icon": "mdi:gamepad",
        "isFullWidth": false,
        "kind": "media",
        "modalItems": [],
        "semantics": {
         "type": "command"
        },
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Handheld Console"
       },
       {
        "action": {
         "action": {
          "command": {
           "call": {
            "data": {},
            "domain": "script",
            "service": "demo_media_room_tv_movie"
           },
           "optimistic": [],
           "type": "service"
          },
          "type": "command"
         },
         "type": "remote"
        },
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "input_boolean.demo_input_boolean_5",
        "icon": "mdi:television",
        "isFullWidth": false,
        "kind": "media",
        "modalItems": [],
        "semantics": {
         "type": "command"
        },
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Media STREAMER"
       }
      ],
      "layout": {
       "leadRow": {}
      },
      "showOnRoomPage": true,
      "title": "Remote"
     },
     {
      "cards": [],
      "layout": {
       "appLaunch": {
        "remoteId": "media-room-streamer"
       }
      },
      "showOnRoomPage": true,
      "title": "Quick App Launch"
     },
     {
      "cards": [
       {
        "action": {
         "action": {
          "cases": [
           {
            "command": {
             "call": {
              "data": {},
              "domain": "input_button",
              "service": "demo_press",
              "target": "input_button.demo_input_button_5"
             },
             "optimistic": [],
             "type": "service"
            },
            "states": [
             "on"
            ]
           }
          ],
          "otherwise": {
           "call": {
            "data": {},
            "domain": "input_button",
            "service": "demo_press",
            "target": "input_button.demo_input_button_6"
           },
           "optimistic": [],
           "type": "service"
          },
          "type": "state"
         },
         "type": "remote"
        },
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "input_boolean.demo_power_1",
        "icon": "mdi:projector",
        "isFullWidth": false,
        "kind": "power",
        "modalItems": [],
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [
         "input_text.demo_power_3"
        ],
        "title": "Media Room Computer"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Media Room Computers"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "vacuum.demo_vacuum_3",
        "icon": "mdi:robot-vacuum",
        "isFullWidth": true,
        "kind": "vacuum",
        "modalItems": [],
        "modalTitle": "Robot Vacuum",
        "sheet": "robot-vacuum",
        "showState": false,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Media room"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Devices"
     }
    ],
    "title": "Media room"
   },
   {
    "id": "downstairs-hallway",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_downstairs_hallway_light_item_1",
      "icon": "mdi:lightbulb",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "light-downstairs-hallway",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Light"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_downstairs_hallway_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-downstairs-hallway",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_downstairs_hallway_presence_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "downstairs-hallway-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_garage_contact_1",
      "icon": "mdi:door",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "door-downstairs-hallway",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Door"
     }
    ],
    "sections": [],
    "title": "Downstairs Hallway"
   },
   {
    "id": "garage",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_garage_1",
      "icon": "mdi:door",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "doors-garage",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Doors"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "input_boolean.demo_input_boolean_6",
        "icon": "mdi:washing-machine",
        "isFullWidth": false,
        "kind": "laundry",
        "modalItems": [],
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Washing Machine"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "input_boolean.demo_input_boolean_7",
        "icon": "mdi:tumble-dryer",
        "isFullWidth": false,
        "kind": "laundry",
        "modalItems": [],
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Dryer"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Appliances"
     },
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "control": "garage-door",
        "disabledStates": [],
        "entityId": "cover.demo_garage_door_1",
        "icon": "mdi:garage",
        "isFullWidth": false,
        "kind": "contact",
        "modalItems": [],
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Left Door"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "control": "garage-door",
        "disabledStates": [],
        "entityId": "cover.demo_garage_door_2",
        "icon": "mdi:garage",
        "isFullWidth": false,
        "kind": "contact",
        "modalItems": [],
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Right Door"
       }
      ],
      "layout": {
       "grid": {}
      },
      "showOnRoomPage": true,
      "title": "Garage Doors"
     }
    ],
    "title": "Garage"
   },
   {
    "id": "guest-bathroom",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_switch_1",
      "icon": "mdi:lightbulb",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-guest-bathroom",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Light"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_input_text_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-overview",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_binary_sensor_9",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "guest-bathroom-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "control": "bathroom-fan",
        "disabledStates": [],
        "entityId": "switch.demo_fan_1",
        "icon": "mdi:fan",
        "isFullWidth": true,
        "kind": "fan",
        "modalItems": [],
        "sheet": "fan-guest-bathroom",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Fan"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_vent_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vent"
       },
       {
        "action": {
         "type": "flip"
        },
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "switch.demo_switch_2",
        "icon": "mdi:heat-wave",
        "isFullWidth": false,
        "kind": "light",
        "modalItems": [],
        "showState": true,
        "stateColors": {
         "on": {
          "blue": 0.10196078431372549,
          "green": 0.25098039215686274,
          "opacity": 0.6,
          "red": 0.5333333333333333
         }
        },
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Towel Rack"
       }
      ],
      "layout": {
       "leadRow": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     }
    ],
    "title": "Guest Bathroom"
   },
   {
    "id": "bathroom-1",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "light.demo_bathroom_1_switch_1",
      "icon": "mdi:lightbulb",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-bathroom-1",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Light"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_input_text_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-overview",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_bathroom_1_presence_1",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "bathroom-1-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     }
    ],
    "sections": [
     {
      "cards": [
       {
        "activeStates": [],
        "climateActionTone": false,
        "control": "bathroom-fan",
        "disabledStates": [],
        "entityId": "switch.demo_bathroom_1_fan_1",
        "icon": "mdi:fan",
        "isFullWidth": true,
        "kind": "fan",
        "modalItems": [],
        "sheet": "fan-bathroom-1",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Fan"
       },
       {
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "cover.demo_bathroom_1_vent_1",
        "icon": "mdi:air-filter",
        "isFullWidth": false,
        "kind": "vent",
        "modalItems": [
         {
          "entityId": "cover.demo_bathroom_1_vent_1",
          "icon": "mdi:air-filter",
          "title": "Vent"
         }
        ],
        "sheet": "vents",
        "showState": true,
        "stateColors": {},
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Vent"
       },
       {
        "action": {
         "type": "flip"
        },
        "activeStates": [],
        "climateActionTone": false,
        "disabledStates": [],
        "entityId": "switch.demo_bathroom_1_switch_1",
        "icon": "mdi:heat-wave",
        "isFullWidth": false,
        "kind": "light",
        "modalItems": [],
        "showState": true,
        "stateColors": {
         "on": {
          "blue": 0.10196078431372549,
          "green": 0.25098039215686274,
          "opacity": 0.6,
          "red": 0.5333333333333333
         }
        },
        "stateLabels": {},
        "subtitleEntityIds": [],
        "title": "Towel Rack"
       }
      ],
      "layout": {
       "leadRow": {}
      },
      "showOnRoomPage": true,
      "title": "Climate"
     }
    ],
    "title": "Bathroom 1"
   },
   {
    "id": "entryway",
    "overviewCards": [
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "switch.demo_entryway_light_1",
      "icon": "mdi:lightbulb",
      "isFullWidth": false,
      "kind": "light",
      "modalItems": [],
      "sheet": "lights-entryway",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Light"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_entryway_presence_2",
      "icon": "mdi:motion-sensor",
      "isFullWidth": false,
      "kind": "occupancy",
      "modalItems": [],
      "sheet": "entryway-occupancy",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Occupancy"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "input_text.demo_front_door_door_1",
      "icon": "mdi:thermometer",
      "isFullWidth": false,
      "kind": "climate",
      "modalItems": [],
      "sheet": "climate-overview",
      "showState": true,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Climate"
     },
     {
      "activeStates": [],
      "climateActionTone": false,
      "disabledStates": [],
      "entityId": "binary_sensor.demo_front_door_contact_1",
      "icon": "mdi:door",
      "isFullWidth": false,
      "kind": "contact",
      "modalItems": [],
      "sheet": "door-entryway",
      "showState": false,
      "stateColors": {},
      "stateLabels": {},
      "subtitleEntityIds": [],
      "title": "Door"
     }
    ],
    "sections": [],
    "title": "Entryway"
   }
  ],
  "quickLinks": [
   {
    "action": {
     "detail": "rooms",
     "type": "detail"
    },
    "icon": "mdi:floor-plan",
    "id": "rooms",
    "title": "Rooms",
    "tone": "climate"
   },
   {
    "action": {
     "detail": "security-system",
     "type": "detail"
    },
    "entityId": "alarm_control_panel.demo_alarm_control_panel_1",
    "icon": "mdi:shield-outline",
    "id": "security-system",
    "status": {
     "entityState": {}
    },
    "title": "Security System",
    "tone": "neutral"
   },
   {
    "action": {
     "path": "food",
     "type": "navigate"
    },
    "backgroundColor": {
     "blue": 0.25098039215686274,
     "green": 0.43137254901960786,
     "opacity": 0.72,
     "red": 0.6078431372549019
    },
    "icon": "mdi:food-fork-drink",
    "id": "food",
    "status": {
     "allFood": {}
    },
    "title": "Food & Recipes",
    "tone": "neutral"
   },
   {
    "action": {
     "path": "vacuums",
     "type": "navigate"
    },
    "icon": "mdi:robot-vacuum",
    "id": "vacuums",
    "title": "Vacuums",
    "tone": "vacuum"
   },
   {
    "action": {
     "path": "media",
     "type": "navigate"
    },
    "icon": "mdi:remote",
    "id": "media",
    "title": "Media",
    "tone": "media"
   },
   {
    "action": {
     "path": "custom-lights",
     "type": "navigate"
    },
    "icon": "mdi:lightbulb-group",
    "id": "custom-lights",
    "title": "Custom Lights",
    "tone": "light"
   },
   {
    "action": {
     "path": "sprinklers",
     "type": "navigate"
    },
    "icon": "mdi:sprinkler-variant",
    "id": "sprinklers",
    "title": "Sprinklers",
    "tone": "neutral",
    "visibilityEntityId": "input_boolean.demo_input_boolean_3"
   }
  ],
  "shared": {
   "bathroomFanSheets": {
    "switch.demo_bathroom_1_fan_1": "fan-bathroom-1",
    "switch.demo_fan_1": "fan-guest-bathroom"
   },
   "dishwasherProgramEntityId": "select.demo_program_1",
   "wakeLightPage": {
    "sectionTitle": "Sleep & Wake",
    "sheet": "wake-light-alarms-bedroom-1",
    "title": "Wake-Light Alarms"
   }
  }
 },
 "schema": 2,
 "security": {
  "alarmEntityId": "alarm_control_panel.demo_alarm_control_panel_1",
  "contactSensorsEntityId": "binary_sensor.demo_contact_2",
  "controlTiles": [
   {
    "entityId": "alarm_control_panel.demo_alarm_control_panel_1",
    "icon": "mdi:shield-outline",
    "kind": "alarm",
    "title": "Security System"
   },
   {
    "entityId": "lock.demo_lock_2",
    "icon": "mdi:lock",
    "kind": "lock",
    "title": "Front Door"
   },
   {
    "entityId": "cover.demo_garage_door_1",
    "icon": "mdi:garage",
    "kind": "garageDoor",
    "title": "Left Door"
   },
   {
    "entityId": "cover.demo_garage_door_2",
    "icon": "mdi:garage",
    "kind": "garageDoor",
    "title": "Right Door"
   }
  ],
  "entryLockEntityId": "lock.demo_lock_2",
  "garageDoors": {
   "left": "cover.demo_garage_door_1",
   "right": "cover.demo_garage_door_2"
  },
  "showsVehicleSection": false,
  "vehicleLockEntityId": "lock.demo_lock_1",
  "vehicleTiles": [
   {
    "entityId": "lock.demo_lock_1",
    "icon": "mdi:car-door-lock",
    "kind": "vehicle",
    "title": "Doors"
   }
  ]
 },
 "sprinklers": {
  "controllers": [
   {
    "batteryEntityId": "sensor.demo_front_yard_battery_1",
    "faultEntityId": "binary_sensor.demo_front_yard_fault_item_1",
    "hubConnectedEntityId": "binary_sensor.demo_front_yard_1",
    "id": "frontYard",
    "modeEntityId": "select.demo_front_yard_mode_1",
    "nextWateringEntityId": "sensor.demo_front_yard_1",
    "rainDelayEntityId": "switch.demo_front_yard_1",
    "smartWateringEntityId": "switch.demo_front_yard_2",
    "stateEntityId": "sensor.demo_front_yard_state_item_1",
    "title": "Front Yard",
    "zones": [
     {
      "historyEntityId": "sensor.demo_front_yard_zone_1",
      "programEntityId": "switch.demo_front_yard_program_1",
      "valveEntityId": "valve.demo_front_yard_zone_item_1"
     }
    ]
   },
   {
    "batteryEntityId": "sensor.demo_backyard_battery_1",
    "faultEntityId": "binary_sensor.demo_backyard_fault_1",
    "hubConnectedEntityId": "binary_sensor.demo_binary_sensor_10",
    "id": "backyard",
    "modeEntityId": "select.demo_backyard_mode_1",
    "nextWateringEntityId": "sensor.demo_backyard_1",
    "rainDelayEntityId": "switch.demo_backyard_1",
    "smartWateringEntityId": "switch.demo_backyard_2",
    "stateEntityId": "sensor.demo_backyard_state_1",
    "title": "Garden Faucet",
    "zones": [
     {
      "historyEntityId": "sensor.demo_zone_1",
      "programEntityId": "switch.demo_backyard_program_1",
      "valveEntityId": "valve.demo_backyard_zone_1"
     },
     {
      "historyEntityId": "sensor.demo_zone_2",
      "programEntityId": "switch.demo_backyard_program_2",
      "valveEntityId": "valve.demo_backyard_zone_2"
     },
     {
      "historyEntityId": "sensor.demo_backyard_zone_1",
      "programEntityId": "switch.demo_backyard_program_3",
      "valveEntityId": "valve.demo_backyard_zone_3"
     },
     {
      "historyEntityId": "sensor.demo_zone_3",
      "programEntityId": "switch.demo_backyard_program_4",
      "valveEntityId": "valve.demo_backyard_zone_4"
     }
    ]
   }
  ],
  "defaultStartTime": "07:00",
  "lowBatteryPercent": 20,
  "visibilityEntityId": "input_boolean.demo_input_boolean_3"
 },
 "vacation": {
  "checklist": [
   {
    "entityId": "input_boolean.demo_input_boolean_8",
    "title": "Turn off outdoor sprinklers"
   },
   {
    "entityId": "input_boolean.demo_input_boolean_9",
    "title": "Flush the drain"
   },
   {
    "entityId": "input_boolean.demo_input_boolean_10",
    "title": "Make the bed"
   },
   {
    "entityId": "input_boolean.demo_input_boolean_11",
    "title": "Unload and Check Dishwasher"
   },
   {
    "entityId": "input_boolean.demo_input_boolean_12",
    "title": "Take out the trash"
   }
  ],
  "endEntityId": "input_datetime.demo_input_datetime_3",
  "invalidDatesPendingEntityId": "input_boolean.demo_mode_4",
  "modeEntityId": "input_boolean.demo_mode_3",
  "startEntityId": "input_datetime.demo_input_datetime_4"
 },
 "vacuums": {
  "autoCleanControls": [
   {
    "entityId": "switch.demo_main_floor_1",
    "icon": "mdi:robot-vacuum",
    "kind": {
     "pause": {}
    },
    "title": "Main Floor"
   },
   {
    "entityId": "automation.demo_studio_1",
    "icon": "mdi:robot-vacuum",
    "kind": {
     "automation": {}
    },
    "title": "Studio"
   },
   {
    "entityId": "automation.demo_media_room_schedule_1",
    "icon": "mdi:robot-vacuum",
    "kind": {
     "automation": {}
    },
    "title": "Media room"
   }
  ],
  "outcomeReconciliations": {
   "mapped_devicea": [
    {
     "entityId": "input_text.demo_living_room_2",
     "roomId": "living_room"
    },
    {
     "entityId": "input_text.demo_bedroom_1_2",
     "roomId": "bedroom_1"
    },
    {
     "entityId": "input_text.demo_main_floor_1",
     "roomId": "kitchen"
    },
    {
     "entityId": "input_text.demo_main_floor_2",
     "roomId": "office"
    },
    {
     "entityId": "input_text.demo_main_floor_3",
     "roomId": "hallway"
    },
    {
     "entityId": "input_text.demo_guest_room_2",
     "roomId": "guest_room"
    },
    {
     "entityId": "input_text.demo_bathroom_1_2",
     "roomId": "bathroom_1"
    },
    {
     "entityId": "input_text.demo_main_floor_4",
     "roomId": "guest_bathroom"
    },
    {
     "entityId": "input_text.demo_main_floor_5",
     "roomId": "gym"
    },
    {
     "entityId": "input_text.demo_bedroom_1_3",
     "roomId": "bedroom_1_closet"
    },
    {
     "entityId": "input_text.demo_dining_room_2",
     "roomId": "dining_room"
    }
   ]
  },
  "vacuums": [
   {
    "areaCleaning": {
     "minimumSizeCm": 25,
     "script": "script.demo_main_floor_zone_1"
    },
    "autoCleanDisabledRooms": [
     {
      "entityId": "switch.demo_living_room_1",
      "icon": "mdi:sofa",
      "title": "Living Room"
     },
     {
      "entityId": "switch.demo_bedroom_1_1",
      "icon": "mdi:bed-double",
      "title": "Bedroom 1"
     },
     {
      "entityId": "switch.demo_main_floor_2",
      "icon": "mdi:fridge",
      "title": "Kitchen"
     },
     {
      "entityId": "switch.demo_main_floor_3",
      "icon": "mdi:laptop",
      "title": "Office"
     },
     {
      "entityId": "switch.demo_main_floor_4",
      "icon": "mdi:wardrobe",
      "title": "Hallway"
     },
     {
      "entityId": "switch.demo_guest_room_1",
      "icon": "mdi:bed",
      "title": "Guest Room"
     },
     {
      "entityId": "switch.demo_bathroom_1_1",
      "icon": "mdi:shower",
      "title": "Bathroom 1"
     },
     {
      "entityId": "switch.demo_main_floor_5",
      "icon": "mdi:shower",
      "title": "Guest Bathroom"
     },
     {
      "entityId": "switch.demo_main_floor_6",
      "icon": "mdi:weight-lifter",
      "title": "Gym"
     },
     {
      "entityId": "switch.demo_bedroom_1_2",
      "icon": "mdi:wardrobe",
      "title": "Closet"
     },
     {
      "entityId": "switch.demo_dining_room_1",
      "icon": "mdi:silverware-fork-knife",
      "title": "Dining Room"
     }
    ],
    "batteryEntityId": "sensor.demo_battery_1",
    "cleanScript": "script.demo_main_floor_1",
    "consumables": [
     {
      "entityId": "sensor.demo_sensor_20",
      "icon": "mdi:brush",
      "title": "Main Brush",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_21",
      "icon": "mdi:brush-variant",
      "title": "Side Brush",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_filter_1",
      "icon": "mdi:air-filter",
      "title": "Main Filter",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_22",
      "icon": "mdi:radar",
      "title": "Sensors",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_23",
      "icon": "mdi:tire",
      "title": "Wheels",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_24",
      "icon": "mdi:delete",
      "title": "Dustbag",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_25",
      "icon": "mdi:water",
      "title": "Fresh Water",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_26",
      "icon": "mdi:water-off",
      "title": "Waste Water",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_27",
      "icon": "mdi:bottle-tonic",
      "title": "Detergent",
      "valueKind": {
       "status": {}
      }
     }
    ],
    "coordinatorSessionEntityId": "sensor.demo_main_floor_state_1",
    "dockButtonEntityId": "button.demo_button_1",
    "dockControls": {
     "cleanScript": "script.demo_main_floor_2",
     "dockStatusEntityId": "sensor.demo_status_2",
     "dryScript": "script.demo_main_floor_3",
     "mopAttachmentEntityId": "binary_sensor.demo_binary_sensor_11"
    },
    "entityId": "vacuum.demo_vacuum_1",
    "errorEntityId": "sensor.demo_error_1",
    "fanEntityId": "select.demo_fan_1",
    "mapRoomSelection": true,
    "mapRotationDegrees": 180,
    "mapScale": 1.2,
    "modeEntityId": "select.demo_mode_3",
    "modeTextEntityId": "input_text.demo_main_floor_mode_1",
    "outcomeRoomNames": {
     "bathroom_1": "Bathroom 1",
     "bedroom_1": "Bedroom 1",
     "bedroom_1_closet": "Bedroom 1 Closet",
     "dining_room": "Dining Room",
     "guest_bathroom": "Guest Bathroom",
     "guest_room": "Guest Room",
     "gym": "Gym",
     "hallway": "Hallway",
     "kitchen": "Kitchen",
     "living_room": "Living Room",
     "office": "Office"
    },
    "passesEntityId": "input_select.demo_main_floor_1",
    "statusEntityId": "sensor.demo_main_floor_status_1",
    "statusFlagEntityId": "sensor.demo_status_3",
    "title": "Main Floor",
    "vacuumMapId": "mapped_devicea",
    "waterEntityId": "select.demo_select_3",
    "zoneDescription": [
     "Select any zones to focus cleaning in those areas. If you press clean and no zones are selected, we will clean all zones on the Main Floor.",
     "Zones are not selectable or changeable while cleaning is ongoing."
    ],
    "zones": [
     {
      "entityId": "input_boolean.demo_living_room_1",
      "icon": "mdi:sofa",
      "mapName": "Living Room",
      "mopRequiredEntityId": "sensor.demo_living_room_3",
      "title": "Living Room"
     },
     {
      "entityId": "input_boolean.demo_bedroom_1_1",
      "icon": "mdi:bed-double",
      "mapName": "Bedroom 1",
      "mopRequiredEntityId": "sensor.demo_bedroom_1_4",
      "title": "Bedroom 1"
     },
     {
      "entityId": "input_boolean.demo_kitchen_1",
      "icon": "mdi:fridge",
      "mapName": "Kitchen",
      "mopRequiredEntityId": "sensor.demo_main_floor_1",
      "title": "Kitchen"
     },
     {
      "entityId": "input_boolean.demo_office_1",
      "icon": "mdi:laptop",
      "mapName": "Office",
      "mopRequiredEntityId": "sensor.demo_main_floor_2",
      "title": "Office"
     },
     {
      "entityId": "input_boolean.demo_hallway_1",
      "icon": "mdi:wardrobe",
      "mapName": "Hallway",
      "mopRequiredEntityId": "sensor.demo_main_floor_3",
      "title": "Hallway"
     },
     {
      "entityId": "input_boolean.demo_guest_room_2",
      "icon": "mdi:bed",
      "mapName": "Guest Room",
      "mopRequiredEntityId": "sensor.demo_guest_room_3",
      "title": "Guest Room"
     },
     {
      "entityId": "input_boolean.demo_bathroom_1_1",
      "icon": "mdi:shower",
      "mapName": "Bathroom 1",
      "mopRequiredEntityId": "sensor.demo_bathroom_1_1",
      "title": "Bathroom 1"
     },
     {
      "entityId": "input_boolean.demo_input_boolean_13",
      "icon": "mdi:shower",
      "mapName": "Guest Bathroom",
      "mopRequiredEntityId": "sensor.demo_main_floor_4",
      "title": "Guest Bathroom"
     },
     {
      "entityId": "input_boolean.demo_gym_1",
      "icon": "mdi:weight-lifter",
      "mapName": "Gym",
      "mopRequiredEntityId": "sensor.demo_main_floor_5",
      "title": "Gym"
     },
     {
      "entityId": "input_boolean.demo_bedroom_1_2",
      "icon": "mdi:wardrobe",
      "mapName": "Bedroom 1 Closet",
      "mopRequiredEntityId": "sensor.demo_bedroom_1_5",
      "title": "Closet"
     },
     {
      "entityId": "input_boolean.demo_dining_room_1",
      "icon": "mdi:silverware-fork-knife",
      "mapName": "Dining Room",
      "mopRequiredEntityId": "sensor.demo_dining_room_1",
      "title": "Dining Room"
     }
    ]
   },
   {
    "areaCleaning": {
     "minimumSizeCm": 25,
     "script": "script.demo_studio_zone_1"
    },
    "autoCleanDisabledRooms": [],
    "batteryEntityId": "sensor.demo_battery_2",
    "cleanScript": "script.demo_studio_1",
    "consumables": [
     {
      "entityId": "sensor.demo_sensor_28",
      "icon": "mdi:brush",
      "title": "Main Brush",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_29",
      "icon": "mdi:brush-variant",
      "title": "Side Brush",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_filter_2",
      "icon": "mdi:air-filter",
      "title": "Main Filter",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_30",
      "icon": "mdi:radar",
      "title": "Sensors",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_31",
      "icon": "mdi:tire",
      "title": "Wheels",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_32",
      "icon": "mdi:delete",
      "title": "Dustbag",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_33",
      "icon": "mdi:water",
      "title": "Fresh Water",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_34",
      "icon": "mdi:water-off",
      "title": "Waste Water",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_35",
      "icon": "mdi:bottle-tonic",
      "title": "Detergent",
      "valueKind": {
       "status": {}
      }
     }
    ],
    "dockButtonEntityId": "button.demo_button_2",
    "dockControls": {
     "cleanScript": "script.demo_studio_2",
     "dockStatusEntityId": "sensor.demo_status_4",
     "dryScript": "script.demo_studio_3",
     "mopAttachmentEntityId": "binary_sensor.demo_binary_sensor_12"
    },
    "entityId": "vacuum.demo_vacuum_2",
    "errorEntityId": "sensor.demo_error_2",
    "fanEntityId": "select.demo_fan_2",
    "mapFocus": {
     "paddingCm": 15,
     "requiredSegments": [
      {
       "id": "3",
       "name": "Studio"
      },
      {
       "id": "10",
       "name": "Downstairs Hallway"
      },
      {
       "id": "12",
       "name": "Bathroom 3"
      }
     ],
     "wallAssociationCm": 20
    },
    "mapRoomSelection": true,
    "mapRotationDegrees": 0,
    "mapScale": 2.4,
    "modeEntityId": "select.demo_mode_4",
    "modeTextEntityId": "input_text.demo_studio_mode_1",
    "outcomeRoomNames": {},
    "passesEntityId": "input_select.demo_studio_1",
    "statusEntityId": "sensor.demo_studio_status_5",
    "statusFlagEntityId": "sensor.demo_status_5",
    "title": "Studio",
    "vacuumMapId": "mapped_deviceb",
    "waterEntityId": "select.demo_select_4",
    "zoneDescription": [
     "Select any zones to focus cleaning in those areas. If you press clean and no zones are selected, we will clean all zones in the Studio.",
     "Zones are not selectable or changeable while cleaning is ongoing."
    ],
    "zones": [
     {
      "entityId": "input_boolean.demo_studio_2",
      "icon": "mdi:guitar-electric",
      "mapName": "Studio",
      "mopRequired": true,
      "title": "Clean Studio"
     },
     {
      "entityId": "input_boolean.demo_downstairs_hallway_1",
      "icon": "mdi:wardrobe",
      "mapName": "Downstairs Hallway",
      "mopRequired": true,
      "title": "Clean Downstairs Hallway"
     },
     {
      "entityId": "input_boolean.demo_bathroom_3_1",
      "icon": "mdi:shower-head",
      "mapName": "Bathroom 3",
      "mopRequired": true,
      "title": "Clean Bathroom 3"
     }
    ]
   },
   {
    "areaCleaning": {
     "minimumSizeCm": 25,
     "script": "script.demo_media_room_zone_1"
    },
    "autoCleanDisabledRooms": [],
    "batteryEntityId": "sensor.demo_battery_3",
    "cleanScript": "script.demo_media_room_1",
    "consumables": [
     {
      "entityId": "sensor.demo_sensor_36",
      "icon": "mdi:brush",
      "title": "Main Brush",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_37",
      "icon": "mdi:brush-variant",
      "title": "Side Brush",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_filter_3",
      "icon": "mdi:air-filter",
      "title": "Main Filter",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_38",
      "icon": "mdi:radar",
      "title": "Sensors",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_39",
      "icon": "mdi:tire",
      "title": "Wheels",
      "valueKind": {
       "duration": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_40",
      "icon": "mdi:delete",
      "title": "Dustbag",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_41",
      "icon": "mdi:water",
      "title": "Fresh Water",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_42",
      "icon": "mdi:water-off",
      "title": "Waste Water",
      "valueKind": {
       "status": {}
      }
     },
     {
      "entityId": "sensor.demo_sensor_43",
      "icon": "mdi:bottle-tonic",
      "title": "Detergent",
      "valueKind": {
       "status": {}
      }
     }
    ],
    "dockButtonEntityId": "button.demo_button_3",
    "dockControls": {
     "cleanScript": "script.demo_media_room_2",
     "dockStatusEntityId": "sensor.demo_status_6",
     "dryScript": "script.demo_media_room_3",
     "mopAttachmentEntityId": "binary_sensor.demo_binary_sensor_13"
    },
    "entityId": "vacuum.demo_vacuum_3",
    "errorEntityId": "sensor.demo_error_3",
    "fanEntityId": "select.demo_fan_3",
    "mapRoomSelection": false,
    "mapRotationDegrees": 0,
    "mapScale": 2.4,
    "modeEntityId": "select.demo_mode_5",
    "outcomeRoomNames": {},
    "passesEntityId": "input_select.demo_media_room_1",
    "statusEntityId": "sensor.demo_media_room_status_1",
    "statusFlagEntityId": "sensor.demo_status_7",
    "title": "Media room",
    "vacuumMapId": "mapped_devicec",
    "waterEntityId": "select.demo_select_5",
    "zoneDescription": [],
    "zones": []
   }
  ]
 }
}
"""#
}
#endif
