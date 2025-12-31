/* 
This script is used to extract all hours from the Google Calendar and
create a Gmail draft with the hours and the rate. The default rate is $500/hr.
*/

function onOpen() {
    const ui = SpreadsheetApp.getUi();
    ui.createMenu('SmartAC Billing')
        .addItem('1. Extract All Hours (Formatted Table)', 'extractSmartACHours')
        .addItem('2. Create Gmail Draft', 'createInvoiceDraft')
        .addToUi();
  }
  
  function extractSmartACHours() {
    const ui = SpreadsheetApp.getUi();
    const SHEET = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    const CAL_ID = 'primary'; 
  
    // Ensure Rate is in E1 (SOW Rate: $500) 
    const rateCell = SHEET.getRange("E1");
    if (rateCell.getValue() === "") rateCell.setValue(500); 
    SHEET.getRange("D1").setValue("Hourly Rate:").setFontWeight("bold");
  
    const startResponse = ui.prompt('Billing Window', 'Enter START Date (MM/DD/YYYY):', ui.ButtonSet.OK_CANCEL);
    if (startResponse.getSelectedButton() !== ui.Button.OK) return;
    const endResponse = ui.prompt('Billing Window', 'Enter END Date (MM/DD/YYYY):', ui.ButtonSet.OK_CANCEL);
    if (endResponse.getSelectedButton() !== ui.Button.OK) return;
  
    const startDate = new Date(startResponse.getResponseText());
    const endDate = new Date(endResponse.getResponseText());
    startDate.setHours(0,0,0,0);
    endDate.setHours(23,59,59,999);
  
    const events = CalendarApp.getCalendarById(CAL_ID).getEvents(startDate, endDate);
  
    SHEET.getRange("A3:E100").clear();
    const headers = ["Date", "Description", "Hours", "Line Total ($)"];
    SHEET.getRange(3, 1, 1, 4).setValues([headers]).setBackground("#45818e").setFontColor("white").setFontWeight("bold");
    
    let currentRow = 4;
    events.forEach(event => {
      let title = event.getTitle() || "No Title";
      if (title.trim().toLowerCase() === "home") return;
      if (event.getGuestList().length > 0) title = "[MEETING] " + title;
  
      let durationMs = event.getEndTime() - event.getStartTime();
      let hours = durationMs / (1000 * 60 * 60);
      
      if (hours > 0) {
        SHEET.appendRow([
          Utilities.formatDate(event.getStartTime(), Session.getScriptTimeZone(), "MM/dd/yyyy"),
          title,
          hours.toFixed(2),
          "=C" + currentRow + "*$E$1" // Formula using Rate in E1
        ]);
        currentRow++;
      }
    });
  
    const totalRow = SHEET.getLastRow() + 2;
    SHEET.getRange(totalRow, 2).setValue("INVOICE TOTAL").setFontWeight("bold");
    SHEET.getRange(totalRow, 4).setFormula("=SUM(D4:D" + (currentRow - 1) + ")").setFontWeight("bold").setNumberFormat("$#,##0.00");
    
    ui.alert("Extraction complete. Please review and delete non-billable rows.");
  }
  
  function createInvoiceDraft() {
    const SHEET = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    const CTO_EMAIL = "matt.robillard@smartac.com"; // [cite: 313]
    const displayValues = SHEET.getDataRange().getDisplayValues();
    
    let grandTotal = "$0.00";
    let tableEndRow = 0;
    let found = false;
  
    for (let i = 0; i < displayValues.length; i++) {
      let cellValue = displayValues[i][1].toString().trim().toUpperCase(); // Check Column B (Index 1)
      if (cellValue === "INVOICE TOTAL") { // Synchronized label 
        grandTotal = displayValues[i][3]; 
        tableEndRow = i; 
        found = true;
        break;
      }
    }
  
    if (!found) {
      SpreadsheetApp.getUi().alert("Error: Could not find label 'INVOICE TOTAL' in Column B.");
      return;
    }
  
    const billableData = displayValues.slice(3, tableEndRow - 1);
    let tableRows = "";
    billableData.forEach((row, index) => {
      if (row[0] !== "" && row[1] !== "") {
        const bgColor = (index % 2 === 0) ? "#ffffff" : "#f6f8f9";
        tableRows += `<tr style="background-color:${bgColor};">
          <td style="border:1px solid #cccccc; padding:2px 8px; text-align:right;">${row[0]}</td>
          <td style="border:1px solid #cccccc; padding:2px 8px;">${row[1]}</td>
          <td style="border:1px solid #cccccc; padding:2px 8px; text-align:right;">${row[2]}</td>
          <td style="border:1px solid #cccccc; padding:2px 8px; text-align:right;">${row[3]}</td>
        </tr>`;
      }
    });
  
    const htmlBody = `<div dir="ltr">Hi Matt,<br><br>Please find my bi-weekly invoice for platform architecture consulting services.<br><br>
      <table border="1" style="border-collapse:collapse; font-family:Arial; font-size:10pt; width:100%;">
        <thead><tr style="background-color:#45818e; color:white; font-weight:bold;">
          <th>Date</th><th>Description</th><th>Hours</th><th>Line Total ($)</th>
        </tr></thead>
        <tbody>${tableRows}
        <tr style="font-weight:bold;">
          <td colspan="2" style="text-align:right;">INVOICE TOTAL</td><td></td><td style="text-align:right;">${grandTotal}</td>
        </tr></tbody>
      </table><br>Total amount: ${grandTotal}<br>Payment Terms: Net 30<br><br>Best,<br>Navneet Kapur<br><br>PS - Auto-generated via App Script. Feedback on bugs is welcome.</div>`;
  
    GmailApp.createDraft(CTO_EMAIL, `Invoice Submission: Navneet Kapur - ${displayValues[0][0] || "12/30/2025"}`, "", {
      htmlBody: htmlBody,
      cc: "nav17kapur@gmail.com"
    });
  
    SpreadsheetApp.getUi().alert("Draft created! Total: " + grandTotal);
  }