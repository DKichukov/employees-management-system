package com.ems.service;

import com.ems.model.Employee;
import com.ems.repository.EmployeeRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

@Service
public class EmployeeServiceImpl implements EmployeeService {
    @Autowired
    private EmployeeRepository empRepo;

    @Override
    public List<Employee> getAllEmployees() {
        return empRepo.findAll();
    }

    @Override
    public void saveEmployee(Employee employee) {
        this.empRepo.save(employee);
    }

    @Override
    public Employee getEmployeeById(Long id) {
        Optional<Employee> optional = empRepo.findById(id);
        Employee employee = null;
        if (optional.isPresent()){
             employee=optional.get();
        }else{
            throw new RuntimeException("Employee not found for id: " + id);
        }
        return employee;
    }

    @Override
    public void deleteEmployeeById(Long id) {
        this.empRepo.deleteById(id);
    }
}
