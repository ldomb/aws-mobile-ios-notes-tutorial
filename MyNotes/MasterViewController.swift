/*
 * Copyright 2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file
 * except in compliance with the License. A copy of the License is located at
 *
 *    http://aws.amazon.com/apache2.0/
 *
 * or in the "license" file accompanying this file. This file is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for
 * the specific language governing permissions and limitations under the License.
 */

import UIKit

class MasterViewController: UITableViewController {
    var analyticsService: AnalyticsService? = nil
    var dataService : DataService? = nil
    var detailViewController: DetailViewController? = nil
    var addButton: UIBarButtonItem? = nil
    var notes = [Note]() {
        didSet {
            // When we do something to the data, reload it.
            tableView.reloadData()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "My Notes"
        
        // Get a reference to the analytics service from the AppDelegate
        analyticsService = (UIApplication.shared.delegate as! AppDelegate).analyticsService
        
        // Get a reference to the data service from the AppDelegate
        dataService = (UIApplication.shared.delegate as! AppDelegate).dataService

        
        // Do any additional setup after loading the view, typically from a nib.
        navigationItem.leftBarButtonItem = editButtonItem

        addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertNewObject(_:)))
        navigationItem.rightBarButtonItem = addButton
        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        clearsSelectionOnViewWillAppear = splitViewController!.isCollapsed
        super.viewWillAppear(animated)
        
        NotificationCenter.default.addObserver(self, selector: #selector(rotated), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
        
        analyticsService?.recordEvent("StartListView", parameters: nil, metrics: nil)
        
        // Load the notes from the data service whenever we refresh
        loadNotesFromDataService()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }
    
    @objc func rotated() {
        switch UIDevice.current.orientation {
        case .landscapeLeft, .landscapeRight:
            print("Rotating to landscape")
        default:
            print("Rotating to portrait")
            if tableView.indexPathForSelectedRow != nil {
                self.performSegue(withIdentifier: "showDetail", sender: (Any).self)
            }
        }
    }

    func loadNotesFromDataService() {
        dataService?.loadNotes() { (notesFromNetwork, error) in
            if error == nil {
                if notesFromNetwork == nil {
                    self.notes = [Note]() // Clear the notes out
                } else {
                    self.notes = notesFromNetwork!
                }
            } else {
                analyticsService?.recordEvent("Error", parameters: ["op":"loadNotes"], metrics: nil)
                showErrorAlert(error?.localizedDescription ?? "Unknown data service error", title: "LoadNotes Error")
            }
        }
    }



    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @objc
    func insertNewObject(_ sender: Any) {
        analyticsService?.recordEvent("AddNewNote", parameters: nil, metrics: nil)
        self.performSegue(withIdentifier: "showDetail", sender: sender)
    }

    // MARK: - Segues
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetail" {
            var note: Note? = nil
            
            // If the sender is the add button, then create a new note, otherwise load the note that you clicked on.
            if let barButton = sender as? UIBarButtonItem {
                if addButton == barButton {
                    note = Note()
                    if let indexPath = tableView.indexPathForSelectedRow {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }
                }
            } else if let indexPath = tableView.indexPathForSelectedRow {
                note = notes[indexPath.row]
            }
            
            if (note != nil) {
                analyticsService?.recordEvent("StartDetailView", parameters: [ "id" : note!.id ?? "unknown" ], metrics: nil)
                let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController
                controller.detailItem = note
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        }
    }

    // MARK: - Table View
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return notes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel!.text = notes[indexPath.row].title ?? ""
        return cell
    }

    // Enable swipe-to-delete
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    // Handle a swipe into swipe-to-delete
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let noteId = notes[indexPath.row].id else {
                analyticsService?.recordEvent("Error", parameters: ["op":"swipeToDelete"], metrics: nil)
                showErrorAlert("Invalid note ID presented for swipe-to-delete", title: "Bad Error")
                return
            }
            
            // Delete the note from the backend
            analyticsService?.recordEvent("DeleteNote", parameters: [ "id" : noteId ], metrics: nil)
            dataService?.deleteNote(noteId) { (error) in
                if error == nil {
                    notes.remove(at: indexPath.row)
                    DispatchQueue.main.async {
                        tableView.reloadData()
                    }
                } else {
                    analyticsService?.recordEvent("Error", parameters: ["op":"deleteNote"], metrics: nil)
                    showErrorAlert(error?.localizedDescription ?? "Unknown Error", title: "Row not removed")
                }
            }
        }
    }
    
    // Display the given error message as an alert pop-up
    func showErrorAlert(_ errorMessage: String, title: String?) {
        let alertController = UIAlertController(title: title ?? "Error", message: errorMessage, preferredStyle: .alert)
        let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
        alertController.addAction(defaultAction)
        present(alertController, animated: true, completion: nil)
    }
}

