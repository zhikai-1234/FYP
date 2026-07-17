#!/bin/bash
echo "Killing all ROS processes..."
pkill -f ros
pkill -f gazebo
pkill -f gzserver
pkill -f gzclient
pkill -f python
sleep 5
echo "Done! ROS reset. Ready to launch."
